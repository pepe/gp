#include "llm-helper.h"

#include "llama.h"

#include <algorithm>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <vector>

struct GpLlmModel {
    llama_model *handle = nullptr;
    const llama_vocab *vocab = nullptr;
    std::string description;
};

struct GpLlmSession {
    GpLlmModel *model = nullptr;
    llama_context *context = nullptr;
    bool busy = false;
};

struct GpLlmGeneration {
    GpLlmSession *session = nullptr;
    llama_sampler *sampler = nullptr;
    int32_t remaining = 0;
    bool done = false;
    std::string pending;
    std::string piece;
};

static std::once_flag backend_once;

static void set_error(char *error, size_t error_size, const char *message) {
    if (error == nullptr || error_size == 0) return;
    const size_t n = std::min(error_size - 1, std::strlen(message));
    std::memcpy(error, message, n);
    error[n] = '\0';
}

static bool valid_utf8(const std::string &text) {
    size_t i = 0;
    while (i < text.size()) {
        const unsigned char c = static_cast<unsigned char>(text[i]);
        size_t n = 0;
        if (c < 0x80) n = 1;
        else if ((c & 0xE0) == 0xC0) n = 2;
        else if ((c & 0xF0) == 0xE0) n = 3;
        else if ((c & 0xF8) == 0xF0) n = 4;
        else return false;
        if (i + n > text.size()) return false;
        for (size_t j = 1; j < n; ++j) {
            if ((static_cast<unsigned char>(text[i + j]) & 0xC0) != 0x80) return false;
        }
        i += n;
    }
    return true;
}

extern "C" GpLlmModel *gp_llm_model_load(const char *path, bool mmap, char *error, size_t error_size) {
    std::call_once(backend_once, llama_backend_init);
    llama_model_params params = llama_model_default_params();
    params.n_gpu_layers = 0;
    params.use_mmap = mmap;
    llama_model *handle = llama_model_load_from_file(path, params);
    if (handle == nullptr) {
        set_error(error, error_size, "unable to load GGUF model");
        return nullptr;
    }
    if (llama_model_has_encoder(handle)) {
        llama_model_free(handle);
        set_error(error, error_size, "encoder or encoder-decoder models are not supported yet");
        return nullptr;
    }
    GpLlmModel *model = new (std::nothrow) GpLlmModel();
    if (model == nullptr) {
        llama_model_free(handle);
        set_error(error, error_size, "out of memory while creating model object");
        return nullptr;
    }
    model->handle = handle;
    model->vocab = llama_model_get_vocab(handle);
    char description[512];
    llama_model_desc(handle, description, sizeof(description));
    model->description.assign(description);
    return model;
}

extern "C" void gp_llm_model_free(GpLlmModel *model) {
    if (model == nullptr) return;
    if (model->handle != nullptr) llama_model_free(model->handle);
    delete model;
}

extern "C" const char *gp_llm_model_description(const GpLlmModel *model) { return model->description.c_str(); }
extern "C" uint64_t gp_llm_model_size(const GpLlmModel *model) { return llama_model_size(model->handle); }
extern "C" uint64_t gp_llm_model_parameters(const GpLlmModel *model) { return llama_model_n_params(model->handle); }
extern "C" int32_t gp_llm_model_context_size(const GpLlmModel *model) { return llama_model_n_ctx_train(model->handle); }

extern "C" int32_t gp_llm_tokenize(const GpLlmModel *model, const char *text, int32_t text_length,
                                     int32_t *tokens, int32_t capacity, bool add_special) {
    return llama_tokenize(model->vocab, text, text_length, tokens, capacity, add_special, false);
}

extern "C" int32_t gp_llm_detokenize(const GpLlmModel *model, const int32_t *tokens, int32_t token_count,
                                       char *text, int32_t capacity, bool remove_special) {
    return llama_detokenize(model->vocab, tokens, token_count, text, capacity, remove_special, false);
}

extern "C" GpLlmSession *gp_llm_session_new(GpLlmModel *model, uint32_t context_size,
                                              uint32_t batch_size, int32_t threads,
                                              char *error, size_t error_size) {
    llama_context_params params = llama_context_default_params();
    if (threads > 0) {
        params.n_threads = threads;
        params.n_threads_batch = threads;
    }
    params.n_ctx = context_size;
    params.n_batch = batch_size;
    params.no_perf = true;
    llama_context *context = llama_init_from_model(model->handle, params);
    if (context == nullptr) {
        set_error(error, error_size, "unable to create inference context");
        return nullptr;
    }
    GpLlmSession *session = new (std::nothrow) GpLlmSession();
    if (session == nullptr) {
        llama_free(context);
        set_error(error, error_size, "out of memory while creating session object");
        return nullptr;
    }
    session->model = model;
    session->context = context;
    return session;
}

extern "C" void gp_llm_session_free(GpLlmSession *session) {
    if (session == nullptr) return;
    if (session->context != nullptr) llama_free(session->context);
    delete session;
}

extern "C" void gp_llm_session_reset(GpLlmSession *session) {
    if (session != nullptr && session->context != nullptr) {
        llama_memory_clear(llama_get_memory(session->context), true);
    }
}

extern "C" uint32_t gp_llm_session_context_size(const GpLlmSession *session) {
    return llama_n_ctx(session->context);
}

extern "C" bool gp_llm_session_busy(const GpLlmSession *session) { return session->busy; }

static void finish_generation(GpLlmGeneration *generation) {
    if (generation->done) return;
    generation->done = true;
    if (generation->sampler != nullptr) {
        llama_sampler_free(generation->sampler);
        generation->sampler = nullptr;
    }
    if (generation->session != nullptr) generation->session->busy = false;
}

extern "C" GpLlmGeneration *gp_llm_generation_new(GpLlmSession *session,
                                                    const char *prompt, int32_t prompt_length,
                                                    int32_t max_tokens, float temperature,
                                                    int32_t top_k, float top_p, float min_p,
                                                    uint32_t seed, char *error, size_t error_size) {
    if (session->busy) {
        set_error(error, error_size, "session already has an active generation");
        return nullptr;
    }
    int32_t count = gp_llm_tokenize(session->model, prompt, prompt_length, nullptr, 0, true);
    if (count == INT32_MIN) {
        set_error(error, error_size, "prompt is too large to tokenize");
        return nullptr;
    }
    count = count < 0 ? -count : count;
    if (count <= 0) {
        set_error(error, error_size, "prompt tokenization produced no tokens");
        return nullptr;
    }
    if (static_cast<uint64_t>(count) + static_cast<uint64_t>(max_tokens) > llama_n_ctx(session->context)) {
        set_error(error, error_size, "prompt and requested output exceed the session context size");
        return nullptr;
    }
    std::vector<llama_token> tokens(static_cast<size_t>(count));
    if (gp_llm_tokenize(session->model, prompt, prompt_length, tokens.data(), count, true) < 0) {
        set_error(error, error_size, "failed to tokenize prompt");
        return nullptr;
    }
    gp_llm_session_reset(session);
    const llama_batch batch = llama_batch_get_one(tokens.data(), count);
    if (llama_decode(session->context, batch) != 0) {
        set_error(error, error_size, "failed to evaluate prompt");
        return nullptr;
    }
    GpLlmGeneration *generation = new (std::nothrow) GpLlmGeneration();
    if (generation == nullptr) {
        set_error(error, error_size, "out of memory while creating generation object");
        return nullptr;
    }
    llama_sampler_chain_params chain_params = llama_sampler_chain_default_params();
    chain_params.no_perf = true;
    generation->sampler = llama_sampler_chain_init(chain_params);
    if (temperature <= 0.0f) {
        llama_sampler_chain_add(generation->sampler, llama_sampler_init_greedy());
    } else {
        if (top_k > 0) llama_sampler_chain_add(generation->sampler, llama_sampler_init_top_k(top_k));
        if (top_p < 1.0f) llama_sampler_chain_add(generation->sampler, llama_sampler_init_top_p(top_p, 1));
        if (min_p > 0.0f) llama_sampler_chain_add(generation->sampler, llama_sampler_init_min_p(min_p, 1));
        llama_sampler_chain_add(generation->sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(generation->sampler, llama_sampler_init_dist(seed));
    }
    generation->session = session;
    generation->remaining = max_tokens;
    session->busy = true;
    return generation;
}

extern "C" void gp_llm_generation_free(GpLlmGeneration *generation) {
    if (generation == nullptr) return;
    finish_generation(generation);
    delete generation;
}

extern "C" int gp_llm_generation_step(GpLlmGeneration *generation,
                                        const char **piece, int32_t *piece_length,
                                        char *error, size_t error_size) {
    if (generation->done) return 0;
    if (generation->remaining <= 0) {
        finish_generation(generation);
        return 0;
    }
    llama_token token = llama_sampler_sample(generation->sampler, generation->session->context, -1);
    if (llama_vocab_is_eog(generation->session->model->vocab, token)) {
        finish_generation(generation);
        return 0;
    }
    char small[256];
    int32_t n = llama_token_to_piece(generation->session->model->vocab, token, small, sizeof(small), 0, false);
    if (n < 0) {
        generation->piece.resize(static_cast<size_t>(-n));
        n = llama_token_to_piece(generation->session->model->vocab, token,
                                 generation->piece.data(), -n, 0, false);
        if (n < 0) {
            set_error(error, error_size, "failed to decode generated token");
            finish_generation(generation);
            return -1;
        }
        generation->pending.append(generation->piece.data(), static_cast<size_t>(n));
    } else {
        generation->pending.append(small, static_cast<size_t>(n));
    }
    const llama_batch batch = llama_batch_get_one(&token, 1);
    if (llama_decode(generation->session->context, batch) != 0) {
        set_error(error, error_size, "failed to evaluate generated token");
        finish_generation(generation);
        return -1;
    }
    --generation->remaining;
    if (!valid_utf8(generation->pending) && generation->remaining > 0) return gp_llm_generation_step(generation, piece, piece_length, error, error_size);
    generation->piece.swap(generation->pending);
    generation->pending.clear();
    *piece = generation->piece.data();
    *piece_length = static_cast<int32_t>(generation->piece.size());
    if (generation->remaining == 0) finish_generation(generation);
    return 1;
}
