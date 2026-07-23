#ifndef GP_LLM_HELPER_H
#define GP_LLM_HELPER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GpLlmModel GpLlmModel;
typedef struct GpLlmSession GpLlmSession;
typedef struct GpLlmGeneration GpLlmGeneration;

GpLlmModel *gp_llm_model_load(const char *path, bool mmap, char *error, size_t error_size);
void gp_llm_model_free(GpLlmModel *model);
const char *gp_llm_model_description(const GpLlmModel *model);
uint64_t gp_llm_model_size(const GpLlmModel *model);
uint64_t gp_llm_model_parameters(const GpLlmModel *model);
int32_t gp_llm_model_context_size(const GpLlmModel *model);

int32_t gp_llm_tokenize(const GpLlmModel *model, const char *text, int32_t text_length,
                        int32_t *tokens, int32_t capacity, bool add_special);
int32_t gp_llm_detokenize(const GpLlmModel *model, const int32_t *tokens, int32_t token_count,
                          char *text, int32_t capacity, bool remove_special);

GpLlmSession *gp_llm_session_new(GpLlmModel *model, uint32_t context_size,
                                 uint32_t batch_size, int32_t threads,
                                 char *error, size_t error_size);
void gp_llm_session_free(GpLlmSession *session);
void gp_llm_session_reset(GpLlmSession *session);
uint32_t gp_llm_session_context_size(const GpLlmSession *session);
bool gp_llm_session_busy(const GpLlmSession *session);

GpLlmGeneration *gp_llm_generation_new(GpLlmSession *session,
                                       const char *prompt, int32_t prompt_length,
                                       int32_t max_tokens, float temperature,
                                       int32_t top_k, float top_p, float min_p,
                                       uint32_t seed, char *error, size_t error_size);
void gp_llm_generation_free(GpLlmGeneration *generation);
int gp_llm_generation_step(GpLlmGeneration *generation,
                           const char **piece, int32_t *piece_length,
                           char *error, size_t error_size);

#ifdef __cplusplus
}
#endif

#endif
