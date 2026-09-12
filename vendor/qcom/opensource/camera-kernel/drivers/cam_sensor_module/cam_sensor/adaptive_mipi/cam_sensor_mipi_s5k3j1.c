/* SPDX-License-Identifier: GPL-2.0-only */
#include "cam_sensor_dev.h"
#include "cam_sensor_mipi_universal.h"
#include "cam_sensor_adaptive_mipi_s5k3j1.h"

const struct cam_mipi_sensor_mode *cam_mipi_s5k3j1_mode(u8 mode)
{
	const struct cam_mipi_sensor_mode * const modes[] = {
		sensor_front_mipi_A_mode,
		sensor_front_mipi_B_mode,
		sensor_front_mipi_C_mode,
		sensor_front_mipi_D_mode,
	};

	if (mode > num_front_mipi_setting || mode >= ARRAY_SIZE(modes))
		mode = 0;
	return modes[mode];
}
