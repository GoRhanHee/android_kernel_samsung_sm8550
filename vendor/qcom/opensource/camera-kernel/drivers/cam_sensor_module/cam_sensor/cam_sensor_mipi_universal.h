/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _CAM_SENSOR_MIPI_UNIVERSAL_H_
#define _CAM_SENSOR_MIPI_UNIVERSAL_H_

#include "cam_sensor_mipi.h"

const struct cam_mipi_sensor_mode *cam_mipi_s5kgn3_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_s5khp2_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_s5k2ld_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_imx564_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_imx258_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_imx258_b5_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_s5k3k1_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_imx754_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_s5k3lu_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_imx374_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_s5k3j1_mode(u8 mode);
const struct cam_mipi_sensor_mode *cam_mipi_imx471_mode(u8 mode);

#endif /* _CAM_SENSOR_MIPI_UNIVERSAL_H_ */
