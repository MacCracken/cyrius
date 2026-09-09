/* Consumer-owned main() making a real libsystemd method call.
 * Nothing samvada-specific. `sd_bus_default_system` alone is NOT enough to
 * trip this — the failure needs a call path that reaches memchr. */
#include <systemd/sd-bus.h>
#include <stdio.h>
#include <unistd.h>
extern void _cyrius_init(void);
extern long alloc_init(void);
extern long probe(void);
int main(void) {
    _cyrius_init(); alloc_init();
    (void)probe();                       /* keeps memchr reachable */
    sd_bus *bus = NULL; sd_bus_error e = SD_BUS_ERROR_NULL;
    sd_bus_message *rep = NULL; const char *path = NULL;
    int r = sd_bus_default_system(&bus);
    printf("sd_bus_default_system -> %d\n", r);
    if (r < 0) return 1;
    r = sd_bus_call_method(bus, "org.freedesktop.login1", "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager", "GetSessionByPID", &e, &rep, "u",
        (unsigned)getpid());
    printf("GetSessionByPID -> %d\n", r);
    if (r < 0) return 1;
    sd_bus_message_read(rep, "o", &path);
    printf("session = %s\n", path ? path : "(null)");
    return 0;
}
