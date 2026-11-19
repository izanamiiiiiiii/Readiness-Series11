#include <stdint.h>
#include <dispatch/dispatch.h>
extern void fitness_summary_adapter_start(void);
extern void replacement(void) __asm__("_fitness_summary_score_init");
extern void original(void) __asm__("_$s11WorkoutCore19ReadinessScoreModelV5score06scaledD08category17activityComponent0I13DrivingFactor06vitalsJ0015overnightVitalsJ00nO9Subscores07daytimeoJ005sleepdJ00rP016algorithmVersion0rD10ComparisonACSdSg_SiSgAA0C8CategoryOSgAqA019WOReadinessActivityL0VSgA2QSayAA18WORecoverySubscoreVGSgA2QA0_SSSgAA05SleepdU0OSgtcfC");
__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *replacee; } interpose = {
    (const void *)(uintptr_t)&replacement, (const void *)(uintptr_t)&original
};
__attribute__((constructor)) static void start_fitness_adapter(void) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ fitness_summary_adapter_start(); }); }
