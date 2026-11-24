#include <stddef.h>
#include <stdint.h>

/* The Elm runtime only needs a handful of C library calls. They stay inside
 * this image so the firmware does not have to export them. */

void *memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = dst;
    const uint8_t *s = src;
    size_t i;
    for (i = 0; i < n; i++) d[i] = s[i];
    return dst;
}

void *memmove(void *dst, const void *src, size_t n) {
    uint8_t *d = dst;
    const uint8_t *s = src;
    size_t i;
    if (d == s || n == 0) return dst;
    if (d < s) {
        for (i = 0; i < n; i++) d[i] = s[i];
    } else {
        for (i = n; i > 0; i--) d[i - 1] = s[i - 1];
    }
    return dst;
}

void *memset(void *dst, int value, size_t n) {
    uint8_t *d = dst;
    size_t i;
    for (i = 0; i < n; i++) d[i] = (uint8_t)value;
    return dst;
}

size_t strlen(const char *s) {
    size_t n = 0;
    if (!s) return 0;
    while (s[n]) n++;
    return n;
}

int strcmp(const char *a, const char *b) {
    if (!a || !b) return (a != NULL) - (b != NULL);
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return (unsigned char)*a - (unsigned char)*b;
}

char *strncpy(char *dst, const char *src, size_t n) {
    size_t i = 0;
    if (!dst || n == 0) return dst;
    if (!src) src = "";
    for (; i + 1 < n && src[i]; i++) dst[i] = src[i];
    for (; i < n; i++) dst[i] = 0;
    return dst;
}

/* First-fit over one heap. Offsets stay valid when the firmware slides the
 * image, because they are written at runtime rather than linked in. */
#define MEOW_HEAP_BYTES (64u * 1024u)
#define MEOW_HEAP_END 0xffffffffu

struct MeowBlock {
    uint32_t size;
    uint32_t next;
};

static uint8_t heap_mem[MEOW_HEAP_BYTES];
static uint32_t free_head;
static int heap_ready;

static struct MeowBlock *block_at(uint32_t off) { return (struct MeowBlock *)(heap_mem + off); }

static void heap_init(void) {
    struct MeowBlock *block = (struct MeowBlock *)heap_mem;
    block->size = MEOW_HEAP_BYTES - (uint32_t)sizeof(struct MeowBlock);
    block->next = MEOW_HEAP_END;
    free_head = 0;
    heap_ready = 1;
}

void *malloc(size_t size) {
    uint32_t need = (uint32_t)((size + 7u) & ~7u);
    uint32_t prev = MEOW_HEAP_END;
    uint32_t cur;
    if (need < 8u) need = 8u;
    if (!heap_ready) heap_init();
    for (cur = free_head; cur != MEOW_HEAP_END;) {
        struct MeowBlock *block = block_at(cur);
        uint32_t next = block->next;
        if (block->size >= need) {
            uint32_t leftover = block->size - need;
            if (leftover >= (uint32_t)sizeof(struct MeowBlock) + 8u) {
                uint32_t split = cur + (uint32_t)sizeof(struct MeowBlock) + need;
                struct MeowBlock *rest = block_at(split);
                rest->size = leftover - (uint32_t)sizeof(struct MeowBlock);
                rest->next = next;
                block->size = need;
                next = split;
            }
            if (prev == MEOW_HEAP_END) free_head = next;
            else block_at(prev)->next = next;
            return (uint8_t *)block + sizeof(struct MeowBlock);
        }
        prev = cur;
        cur = next;
    }
    return NULL;
}

void free(void *ptr) {
    struct MeowBlock *block;
    uint32_t off;
    uint32_t prev = MEOW_HEAP_END;
    uint32_t cur;
    if (!ptr) return;
    block = (struct MeowBlock *)((uint8_t *)ptr - sizeof(struct MeowBlock));
    off = (uint32_t)((uint8_t *)block - heap_mem);
    cur = free_head;
    while (cur != MEOW_HEAP_END && cur < off) {
        prev = cur;
        cur = block_at(cur)->next;
    }
    block->next = cur;
    if (prev == MEOW_HEAP_END) free_head = off;
    else block_at(prev)->next = off;
    if (block->next != MEOW_HEAP_END &&
        off + (uint32_t)sizeof(struct MeowBlock) + block->size == block->next) {
        struct MeowBlock *next = block_at(block->next);
        block->size += (uint32_t)sizeof(struct MeowBlock) + next->size;
        block->next = next->next;
    }
    if (prev != MEOW_HEAP_END) {
        struct MeowBlock *before = block_at(prev);
        if (prev + (uint32_t)sizeof(struct MeowBlock) + before->size == off) {
            before->size += (uint32_t)sizeof(struct MeowBlock) + block->size;
            before->next = block->next;
        }
    }
}
