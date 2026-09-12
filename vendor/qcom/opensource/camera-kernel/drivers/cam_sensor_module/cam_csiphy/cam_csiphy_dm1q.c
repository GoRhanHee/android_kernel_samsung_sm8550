/* SPDX-License-Identifier: GPL-2.0-only */
#include "cam_csiphy_soc.h"
#include "cam_csiphy_universal.h"
#include "include/cam_csiphy_2_1_2_hwreg.h"

struct csiphy_ctrl_t *cam_csiphy_dm1q_ctrl(void)
{
	return &ctrl_reg_2_1_2;
}
