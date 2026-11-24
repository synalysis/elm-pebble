/**
 * MeowKit loader name for the portable handheld host ABI.
 * Flipper firmware includes handheld_host.h directly and does not use the loader.
 */
#ifndef MEOW_HOST_H
#define MEOW_HOST_H

#include "handheld_host.h"

typedef HandheldHost MeowHost;
typedef HandheldHostCoreV1 MeowHostCoreV1;
typedef HandheldHostGraphicsV1 MeowHostGraphicsV1;
typedef HandheldHostInputV1 MeowHostInputV1;
typedef HandheldHostSensorsV1 MeowHostSensorsV1;
typedef HandheldHostHapticsV1 MeowHostHapticsV1;
typedef HandheldHostFsV1 MeowHostFsV1;
typedef HandheldHostNfcV1 MeowHostNfcV1;
typedef HandheldHostIrV1 MeowHostIrV1;
typedef HandheldHostUsbV1 MeowHostUsbV1;
typedef HandheldHostRadioV1 MeowHostRadioV1;
typedef HandheldHostGpioV1 MeowHostGpioV1;

#define MEOW_ABI_MAJOR HANDHELD_ABI_MAJOR
#define MEOW_ABI_MINOR HANDHELD_ABI_MINOR

#endif
