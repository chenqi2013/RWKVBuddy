#include "llama.h"
#include "chat.h"
#include "sampling.h"
#include "json-schema-to-grammar.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <condition_variable>
#include <deque>
#include <iostream>
#include <mutex>
#include <thread>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

using json = common_json;
static std::atomic<bool> cancelled{false};
static void emit(const json & value) { std::cout << value.dump() << '\n' << std::flush; }
static void check_cancel() { if (cancelled.load()) throw std::runtime_error("Inference cancelled"); }

// Buffer incomplete UTF-8 tokens instead of replacing split Chinese/emoji bytes.
static bool complete_utf8(const std::string & text) {
    for (size_t i = 0; i < text.size();) {
        const unsigned char first = text[i];
        size_t count = first < 0x80 ? 1 : (first & 0xe0) == 0xc0 ? 2 : (first & 0xf0) == 0xe0 ? 3 : (first & 0xf8) == 0xf0 ? 4 : 0;
        if (!count) throw std::runtime_error("Invalid UTF-8 generated");
        if (i + count > text.size()) return false;
        for (size_t j = 1; j < count; ++j) if ((text[i+j] & 0xc0) != 0x80) throw std::runtime_error("Invalid UTF-8 generated");
        i += count;
    }
    return true;
}

struct Engine {
    llama_model * model = nullptr;
    llama_context * ctx = nullptr;
    common_chat_templates_ptr templates;
    ~Engine() { reset(); }
    void reset() { templates.reset(); if (ctx) llama_free(ctx); ctx = nullptr; if (model) llama_model_free(model); model = nullptr; }
    void load(const json & command, const std::string & id) {
        reset();
        const std::string path = command.at("path").get<std::string>();
        auto params = llama_model_default_params();
        params.n_gpu_layers = 0;
#ifdef __APPLE__
        params.n_gpu_layers = -1;
#endif
        params.progress_callback = [](float progress, void * data) {
            auto * previous = static_cast<int *>(data);
            int percent = static_cast<int>(progress * 100);
            if (percent != *previous) { *previous = percent; emit({{"type", "progress"}, {"percent", percent}}); }
            return !cancelled.load();
        };
        int progress = -1;
        params.progress_callback_user_data = &progress;
        model = llama_model_load_from_file(path.c_str(), params);
        check_cancel();
        if (!model) throw std::runtime_error("Cannot load GGUF: check architecture, file integrity and available memory");
        auto cp = llama_context_default_params();
        cp.n_ctx = command.value("context", 8192);
        cp.n_batch = 256;
        cp.n_ubatch = 256;
        cp.n_seq_max = 1;
        cp.n_threads = command.value("threads", 4);
        cp.n_threads_batch = cp.n_threads;
        cp.abort_callback = [](void *) { return cancelled.load(); };
        ctx = llama_init_from_model(model, cp);
        check_cancel();
        if (!ctx) throw std::runtime_error("Cannot create model context");
        if (!llama_model_chat_template(model, nullptr)) throw std::runtime_error("GGUF has no chat template; use a chat/instruct model");
        templates = common_chat_templates_init(model, "");
        emit({{"type", "ready"}, {"id", id}, {"context", llama_n_ctx(ctx)}, {"transport", "stdio"}});
    }
    void generate(const json & command, const std::string & id) {
        if (!ctx || !templates) throw std::runtime_error("Load a GGUF model first");
        const int max_tokens = command.value("max_tokens", 1024);
        const float temperature = command.value("temperature", 0.2f);
        if (max_tokens < 1 || max_tokens > 8192 || !std::isfinite(temperature) || temperature < 0 || temperature > 2) throw std::runtime_error("Invalid generation parameters");
        common_chat_templates_inputs inputs;
        inputs.enable_thinking = false;
        inputs.reasoning_format = COMMON_REASONING_FORMAT_NONE;
        inputs.force_pure_content = true;
        inputs.chat_template_kwargs["enable_thinking"] = "false";
        for (const auto & item : command.at("messages")) {
            common_chat_msg msg;
            msg.role = item.at("role").get<std::string>();
            if (msg.role != "system" && msg.role != "user" && msg.role != "assistant") throw std::runtime_error("Unsupported message role");
            msg.content = item.at("content").get<std::string>();
            inputs.messages.push_back(std::move(msg));
        }
        if (inputs.messages.empty()) throw std::runtime_error("Messages cannot be empty");
        inputs.json_schema = "{\"type\":\"object\"}";
        auto rendered = common_chat_templates_apply(templates.get(), inputs);
        const auto prompt = rendered.prompt.str();
        const auto vocab = llama_model_get_vocab(model);
        int count = -llama_tokenize(vocab, prompt.data(), static_cast<int>(prompt.size()), nullptr, 0, true, true);
        if (count < 1 || count + max_tokens > static_cast<int>(llama_n_ctx(ctx))) throw std::runtime_error("Input plus output exceeds local context limit; shorten documents or output");
        std::vector<llama_token> tokens(count);
        if (llama_tokenize(vocab, prompt.data(), static_cast<int>(prompt.size()), tokens.data(), count, true, true) < 0) throw std::runtime_error("Tokenization failed");
        llama_memory_clear(llama_get_memory(ctx), true);
        common_params_sampling sp;
        sp.temp = temperature;
        sp.top_p = 0.9f;
        sp.top_k = 40;
        // Pure content output starts at JSON; the model chat prefix is already
        // in the prompt and must not be fed into this content-only grammar.
        sp.grammar = common_grammar(COMMON_GRAMMAR_TYPE_USER,
            json_schema_to_grammar(json::parse(inputs.json_schema), true));
        common_sampler_ptr sampler(common_sampler_init(model, sp));
        if (!sampler) throw std::runtime_error("Cannot initialize JSON sampler");
        auto * batch = llama_batch_ext_init(ctx);
        struct BatchGuard { llama_batch_ext * value; ~BatchGuard() { llama_batch_ext_free(value); } } guard{batch};
        auto decode = [&](const llama_token * data, int size, int position) {
            check_cancel();
            llama_batch_ext_clear(batch);
            for (int i = 0; i < size; ++i) {
                const int idx = llama_batch_ext_add_token(batch, 0, data[i]);
                const llama_pos pos = position + i;
                if (idx < 0 || !llama_batch_ext_set_pos(batch, idx, &pos)) throw std::runtime_error("Invalid inference batch");
            }
            llama_batch_ext_set_output_logits(batch, size - 1, true);
            const int result = llama_process(ctx, LLAMA_PROCESS_TYPE_DECODE, batch);
            check_cancel();
            if (result != 0) throw std::runtime_error("Model decoding failed: " + std::to_string(result));
        };
        emit({{"type", "prefill"}, {"id", id}, {"prompt_tokens", count}});
        for (int offset = 0; offset < count; offset += 256) decode(tokens.data() + offset, std::min(256, count - offset), offset);
        std::string pending;
        std::string finish = "length";
        int generated = 0;
        for (int i = 0; i < max_tokens; ++i) {
            check_cancel();
            const llama_token token = common_sampler_sample(sampler.get(), ctx, -1);
            if (llama_vocab_is_eog(vocab, token)) { finish = "stop"; break; }
            common_sampler_accept(sampler.get(), token, true);
            std::vector<char> piece(256);
            int length = llama_token_to_piece(vocab, token, piece.data(), static_cast<int>(piece.size()), 0, false);
            if (length < 0) { piece.resize(-length); length = llama_token_to_piece(vocab, token, piece.data(), static_cast<int>(piece.size()), 0, false); }
            if (length < 0) throw std::runtime_error("Token decoding failed");
            pending.append(piece.data(), length);
            ++generated;
            if (complete_utf8(pending)) { emit({{"type", "delta"}, {"id", id}, {"text", pending}, {"completion_tokens", generated}}); pending.clear(); }
            if (i + 1 < max_tokens) decode(&token, 1, count + i);
        }
        if (!pending.empty()) throw std::runtime_error("Incomplete UTF-8 at output limit");
        emit({{"type", "done"}, {"id", id}, {"finish_reason", finish}, {"completion_tokens", generated}, {"prompt_tokens", count}});
    }
};

int main(int argc, char ** argv) {
    if (argc > 1 && std::string(argv[1]) == "--version") {
        std::cout << "RWKVBuddy native GGUF inference (stdio, no HTTP)\n";
        return 0;
    }
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    llama_backend_init();
    llama_log_set([](ggml_log_level level, const char * text, void *) {
        if (level >= GGML_LOG_LEVEL_INFO) std::cerr << text;
    }, nullptr);
    std::mutex mutex;
    std::condition_variable changed;
    std::deque<json> queue;
    bool closed = false;
    std::string active_id;
    std::thread reader([&]() {
        std::string line;
        while (std::getline(std::cin, line)) {
            std::lock_guard<std::mutex> lock(mutex);
            try {
                if (line.size() > 2 * 1024 * 1024) throw std::runtime_error("Command too large");
                auto command = json::parse(line);
                const auto type = command.value("type", std::string());
                if (type == "cancel") {
                    const auto target = command.value("id", std::string());
                    if (target == active_id) cancelled.store(true);
                    for (auto & queued : queue) if (queued.value("id", std::string()) == target) queued["cancelled"] = true;
                }
                else if (type == "shutdown") { closed = true; cancelled.store(true); changed.notify_one(); return; }
                else if (queue.size() < 4) { queue.push_back(std::move(command)); changed.notify_one(); }
                else { closed = true; cancelled.store(true); changed.notify_one(); return; }
            } catch (...) { closed = true; cancelled.store(true); changed.notify_one(); return; }
        }
        std::lock_guard<std::mutex> lock(mutex);
        closed = true; cancelled.store(true); changed.notify_one();
    });
    {
        Engine engine;
        while (true) {
            json command;
            {
                std::unique_lock<std::mutex> lock(mutex);
                changed.wait(lock, [&]() { return closed || !queue.empty(); });
                if (closed) break;
                command = std::move(queue.front()); queue.pop_front();
                active_id = command.value("id", std::string());
                cancelled.store(command.value("cancelled", false));
            }
            const std::string id = active_id;
            try {
                check_cancel();
                const std::string type = command.value("type", std::string());
                if (type == "load") engine.load(command, id);
                else if (type == "generate") engine.generate(command, id);
                else throw std::runtime_error("Unknown native command");
            } catch (const std::exception & error) {
                emit({{"type", "error"}, {"id", id}, {"message", error.what()}, {"cancelled", cancelled.load()}});
            }
            std::lock_guard<std::mutex> lock(mutex);
            active_id.clear();
        }
    }
    reader.join();
    llama_backend_free();
    return 0;
}
