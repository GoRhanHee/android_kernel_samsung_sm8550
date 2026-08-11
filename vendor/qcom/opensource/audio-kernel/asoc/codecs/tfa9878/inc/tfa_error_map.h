/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Error conversion helpers between enum tfa_error and enum tfa98xx_error
 */
#ifndef TFA_ERROR_CONVERT_H_
#define TFA_ERROR_CONVERT_H_

#include "tfa.h"        /* for enum tfa_error */
#include "tfa_service.h"    /* for enum tfa98xx_error */

static inline enum tfa98xx_error tfa_to_tfa98xx_err(enum tfa_error err)
{
    switch (err) {
    case tfa_error_ok:
        return TFA98XX_ERROR_OK;
    case tfa_error_device:
        return TFA98XX_ERROR_DEVICE;
    case tfa_error_bad_param:
        return TFA98XX_ERROR_BAD_PARAMETER;
    case tfa_error_noclock:
        return TFA98XX_ERROR_NO_CLOCK;
    case tfa_error_timeout:
        return TFA98XX_ERROR_STATE_TIMED_OUT;
    case tfa_error_dsp:
        return TFA98XX_ERROR_DSP_NOT_RUNNING;
    case tfa_error_container:
        return TFA98XX_ERROR_OTHER;
    default:
        return TFA98XX_ERROR_OTHER;
    }
}

static inline enum tfa_error tfa98xx_to_tfa_err(enum tfa98xx_error err)
{
    switch (err) {
    case TFA98XX_ERROR_OK:
        return tfa_error_ok;
    case TFA98XX_ERROR_DEVICE:
        return tfa_error_device;
    case TFA98XX_ERROR_BAD_PARAMETER:
        return tfa_error_bad_param;
    case TFA98XX_ERROR_NO_CLOCK:
        return tfa_error_noclock;
    case TFA98XX_ERROR_STATE_TIMED_OUT:
        return tfa_error_timeout;
    case TFA98XX_ERROR_DSP_NOT_RUNNING:
        return tfa_error_dsp;
    default:
        return tfa_error_container;
    }
}

#endif /* TFA_ERROR_CONVERT_H_ */
