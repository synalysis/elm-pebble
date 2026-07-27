#include "elmc_generated.h"
#include "elmc_generated.c"
#include <stdio.h>

int main(void) {
  ElmcValue *result = NULL;
  RC rc = elmc_fn_ResultAndThenDirect_pipeline(&result, 0);
  fprintf(stderr, "pipeline rc=%u result=%p", (unsigned)rc, (void *)result);
  if (result) {
    fprintf(stderr, " tag=%d", (int)result->tag);
    if (result->tag == ELMC_TAG_RESULT && result->payload) {
      ElmcResult *r = (ElmcResult *)result->payload;
      fprintf(stderr, " is_ok=%d", r->is_ok ? 1 : 0);
      fprintf(stderr, " ok_match=%d", elmc_union_tag_matches(result, ELMC_UNION_RESULT_OK) ? 1 : 0);
      if (r->is_ok && r->value) {
        fprintf(stderr, " acc=%lld",
                (long long)ELMC_RECORD_GET_INDEX_INT(r->value, ELMC_FIELD_RESULTANDTHENDIRECT_STATE_ACC));
      }
    }
  }
  fprintf(stderr, "\n");

  ElmcValue *sum = NULL;
  rc = elmc_fn_ResultAndThenDirect_runPipeline(&sum, 0, 100);
  fprintf(stderr, "runPipeline rc=%u sum=%p", (unsigned)rc, (void *)sum);
  if (sum) fprintf(stderr, " val=%lld", (long long)elmc_as_int(sum));
  fprintf(stderr, "\n");
  elmc_release(result);
  elmc_release(sum);
  return 0;
}
