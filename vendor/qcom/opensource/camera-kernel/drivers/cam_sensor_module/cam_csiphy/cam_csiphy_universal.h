/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _CAM_CSIPHY_UNIVERSAL_H_
#define _CAM_CSIPHY_UNIVERSAL_H_

#include "cam_csiphy_dev.h"

struct csiphy_ctrl_t *cam_csiphy_dm1q_ctrl(void);
struct csiphy_ctrl_t *cam_csiphy_dm2q_ctrl(void);
struct csiphy_ctrl_t *cam_csiphy_dm3q_ctrl(void);
struct csiphy_ctrl_t *cam_csiphy_q5q_ctrl(void);
struct csiphy_ctrl_t *cam_csiphy_b5q_ctrl(void);

#endif /* _CAM_CSIPHY_UNIVERSAL_H_ */
