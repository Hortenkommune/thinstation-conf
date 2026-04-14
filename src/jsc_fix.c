#define _GNU_SOURCE
#include <signal.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <pthread.h>
#include <string.h>
#include <stdio.h>

#define JSC_ORIG SIGUSR1
#define JSC_NEW  48

static int (*real_sigaction)(int, const struct sigaction *, struct sigaction *) = NULL;
static int (*real_pthread_kill)(pthread_t, int) = NULL;
static int active = 1;

__attribute__((constructor))
void init(void) {
    char buf[256] = {0};
    FILE *f = fopen("/proc/self/comm", "r");
    if (f) {
        fgets(buf, sizeof(buf), f);
        fclose(f);
        char *nl = strchr(buf, '\n');
        if (nl) *nl = '\0';

        if (strcmp(buf, "wfica") == 0) {
            active = 0;
            unsetenv("LD_PRELOAD");
            return;
        }
    }
}

int sigaction(int sig, const struct sigaction *act, struct sigaction *oldact) {
    if (!real_sigaction)
        real_sigaction = dlsym(RTLD_NEXT, "sigaction");
    if (active && sig == JSC_ORIG)
        return real_sigaction(JSC_NEW, act, oldact);
    return real_sigaction(sig, act, oldact);
}

int pthread_kill(pthread_t thread, int sig) {
    if (!real_pthread_kill)
        real_pthread_kill = dlsym(RTLD_NEXT, "pthread_kill");
    if (active && sig == JSC_ORIG)
        return real_pthread_kill(thread, JSC_NEW);
    return real_pthread_kill(thread, sig);
}
