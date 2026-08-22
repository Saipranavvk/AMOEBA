/*
 * tc_semaphore_counting.c — FreeRTOS counting-semaphore stress test.
 *
 * The N-dimensional companion to tc_semaphore.c.  Where that test is a single
 * giver handshaking with a single taker over a binary semaphore, this one puts
 * NUM_GIVERS producers and NUM_TAKERS consumers in contention on one counting
 * semaphore of depth SEM_MAX_COUNT.
 *
 * Semantics carry over from tc_semaphore.c unchanged: givers give a fixed
 * number of times, takers take with portMAX_DELAY and count their successes,
 * and the test passes when the totals agree.
 *
 * Two properties are checked that a binary semaphore cannot satisfy:
 *   - the semaphore holds SEM_MAX_COUNT tokens at once (pre-flight phase);
 *   - tokens genuinely stack up while givers and takers run concurrently,
 *     rather than the pair degenerating into a one-token ping-pong.
 *
 * Exit codes:
 *   0 = PASS
 *   1 = total take count wrong
 *   2 = semaphore create failed
 *   3 = semaphore does not hold SEM_MAX_COUNT tokens
 *   4 = tokens left over after the drain
 *   5 = concurrent pending depth never reached BURST
 *   6 = task create failed
 *   7 = a give was rejected
 */

#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "test_utils_freertos.h"

#define NUM_GIVERS       4
#define NUM_TAKERS       4
#define GIVES_PER_GIVER  8
#define TAKES_PER_TAKER  8

/* Gives issued back-to-back, with no blocking call in between. */
#define BURST            4

#define TOTAL_GIVES      (NUM_GIVERS * GIVES_PER_GIVER)
#define TOTAL_TAKES      (NUM_TAKERS * TAKES_PER_TAKER)

/*
 * Sizing the semaphore to hold every token the givers will ever produce is
 * what makes this test schedule-independent.  A give can only fail when the
 * semaphore is already at its maximum count, and that is now unreachable, so
 * no ordering of the eight tasks can silently drop a token the way an
 * over-full binary semaphore does (see the comment in tc_semaphore.c).
 */
#define SEM_MAX_COUNT    TOTAL_GIVES

_Static_assert(TOTAL_GIVES == TOTAL_TAKES,
               "every token given must be taken, or a taker blocks forever");
_Static_assert(GIVES_PER_GIVER % BURST == 0,
               "each giver must issue a whole number of bursts");

static SemaphoreHandle_t s_sem;   /* the semaphore under test */
static SemaphoreHandle_t s_done;  /* join: each taker gives once on the way out */

/* One slot per task, so the workers never write the same word. */
static volatile UBaseType_t s_taken[NUM_TAKERS];
static volatile UBaseType_t s_depth_seen[NUM_GIVERS];

static void giver(void *pv)
{
    const int id = (int)(uintptr_t)pv;
    UBaseType_t peak = 0;

    for (int done = 0; done < GIVES_PER_GIVER; done += BURST) {
        /*
         * The takers run at a lower priority, so the scheduler cannot switch
         * to one part-way through this burst — a tick landing here can only
         * pick another giver, which pushes the count further up.  Nothing can
         * decrement the semaphore until every giver is blocked in the
         * vTaskDelay below, so the count observed after the last give of the
         * burst is at least BURST regardless of how the tasks interleave.
         */
        for (int i = 0; i < BURST; i++) {
            check(xSemaphoreGive(s_sem) == pdTRUE, 7);
            UBaseType_t depth = uxSemaphoreGetCount(s_sem);
            if (depth > peak)
                peak = depth;
        }
        s_depth_seen[id] = peak;
        vTaskDelay(1); /* release the takers, and interleave with the other givers */
    }
    vTaskDelete(NULL);
}

static void taker(void *pv)
{
    const int id = (int)(uintptr_t)pv;
    UBaseType_t count = 0;

    for (int i = 0; i < TAKES_PER_TAKER; i++) {
        if (xSemaphoreTake(s_sem, portMAX_DELAY) == pdTRUE)
            count++;
    }
    s_taken[id] = count;
    xSemaphoreGive(s_done);
    vTaskDelete(NULL);
}

int app_main(void)
{
    s_sem  = xSemaphoreCreateCounting(SEM_MAX_COUNT, 0);
    s_done = xSemaphoreCreateCounting(NUM_TAKERS, 0);
    if (!s_sem || !s_done)
        return 2;

    /*
     * Pre-flight.  Fill the semaphore to SEM_MAX_COUNT and drain it again
     * while the root task is the only thing running, which proves the depth
     * without depending on the scheduler at all — a binary semaphore saturates
     * at one token and fails the count check immediately.  The phase is
     * balanced, so it leaves the accounting of the concurrent phase untouched.
     */
    for (UBaseType_t i = 0; i < SEM_MAX_COUNT; i++)
        check(xSemaphoreGive(s_sem) == pdTRUE, 3);
    check(uxSemaphoreGetCount(s_sem) == SEM_MAX_COUNT, 3);
    for (UBaseType_t i = 0; i < SEM_MAX_COUNT; i++)
        check(xSemaphoreTake(s_sem, 0) == pdTRUE, 3);
    check(uxSemaphoreGetCount(s_sem) == 0, 3);

    /*
     * Takers first and at the lower priority, matching tc_semaphore.c: they
     * are queued up before the first give, and keeping them below the givers
     * is what the burst-depth argument above rests on.  Here the ordering is
     * only a way of provoking depth, not a correctness requirement — with
     * SEM_MAX_COUNT == TOTAL_GIVES the handshake completes under any schedule.
     */
    for (int i = 0; i < NUM_TAKERS; i++)
        check(xTaskCreate(taker, "taker", configMINIMAL_STACK_SIZE,
                          (void *)(uintptr_t)i, tskIDLE_PRIORITY + 1, NULL) == pdPASS, 6);
    for (int i = 0; i < NUM_GIVERS; i++)
        check(xTaskCreate(giver, "giver", configMINIMAL_STACK_SIZE,
                          (void *)(uintptr_t)i, tskIDLE_PRIORITY + 2, NULL) == pdPASS, 6);

    /* Block until every taker has retired; the root task is idle from here. */
    for (int i = 0; i < NUM_TAKERS; i++)
        xSemaphoreTake(s_done, portMAX_DELAY);

    UBaseType_t total = 0;
    for (int i = 0; i < NUM_TAKERS; i++)
        total += s_taken[i];
    check(total == TOTAL_TAKES, 1);

    /* All TOTAL_TAKES takes succeeded, so all TOTAL_GIVES gives landed. */
    check(uxSemaphoreGetCount(s_sem) == 0, 4);

    UBaseType_t peak = 0;
    for (int i = 0; i < NUM_GIVERS; i++)
        if (s_depth_seen[i] > peak)
            peak = s_depth_seen[i];
    check(peak >= BURST, 5);

    tohost_exit(0);
    return 0; /* unreachable */
}
