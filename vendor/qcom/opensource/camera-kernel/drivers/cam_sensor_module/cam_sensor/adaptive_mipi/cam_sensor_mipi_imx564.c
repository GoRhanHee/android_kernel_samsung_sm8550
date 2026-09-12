/* SPDX-License-Identifier: GPL-2.0-only */
#include "cam_sensor_dev.h"
#include "cam_sensor_mipi_universal.h"
#include "cam_sensor_adaptive_mipi_imx564.h"

const struct cam_mipi_sensor_mode *cam_mipi_imx564_mode(u8 mode)
{
	const struct cam_mipi_sensor_mode * const modes[] = {
		sensor_uw_mipi_A_mode,
		sensor_uw_mipi_B_mode,
		sensor_uw_mipi_C_mode,
		sensor_uw_mipi_D_mode,
	};

	if (mode > num_uw_mipi_setting || mode >= ARRAY_SIZE(modes))
		mode = 0;
	return modes[mode];
}
