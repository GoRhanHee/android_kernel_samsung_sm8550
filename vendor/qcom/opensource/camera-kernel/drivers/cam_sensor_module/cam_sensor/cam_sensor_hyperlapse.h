/* SPDX-License-Identifier: GPL-2.0-only */
/* Samsung hyperlapse sequences selected by sensor ID. */
#ifndef _CAM_SENSOR_HYPERLAPSE_H_
#define _CAM_SENSOR_HYPERLAPSE_H_

static struct cam_sensor_i2c_reg_array gn3_fll_setting[] = {
  {0x0104, 0x0101, 0, 0},
  {0x0702, 0x0000, 0, 0},
  {0x0704, 0x0000, 0, 0},
  {0x0340, 0x1AB4, 0, 0},
  {0x0202, 0x0D11, 0, 0},
  {0x0204, 0x0063, 0, 0},
  {0x020E, 0x0100, 0, 0},
  {0x0104, 0x0001, 0, 0},
 };

static const struct cam_sensor_i2c_reg_setting gn3_fll_settings[] = {
	{ gn3_fll_setting, ARRAY_SIZE(gn3_fll_setting),
	  CAMERA_SENSOR_I2C_TYPE_WORD, CAMERA_SENSOR_I2C_TYPE_WORD, 0 },
};

static struct cam_sensor_i2c_reg_array gn3_streamoff_setting[] = {
  {0x0B32, 0x0000, 0, 0},
  {0x0E00, 0x0003, 0, 0},
  {0x0100, 0x0003, 0, 0},
 };

static const struct cam_sensor_i2c_reg_setting gn3_streamoff_settings[] = {
	{ gn3_streamoff_setting, ARRAY_SIZE(gn3_streamoff_setting),
	  CAMERA_SENSOR_I2C_TYPE_WORD, CAMERA_SENSOR_I2C_TYPE_WORD, 0 },
};

static struct cam_sensor_i2c_reg_array gn3_streamon_setting[] = {
  {0x0B32, 0x0000, 0, 0},
  {0x0100, 0x0103, 0, 0},
 };

static const struct cam_sensor_i2c_reg_setting gn3_streamon_settings[] = {
	{ gn3_streamon_setting, ARRAY_SIZE(gn3_streamon_setting),
	  CAMERA_SENSOR_I2C_TYPE_WORD, CAMERA_SENSOR_I2C_TYPE_WORD, 0 },
};

static struct cam_sensor_i2c_reg_array hp2_fll_setting[] = {
  {0x0104, 0x0101, 0, 0},
  {0x0702, 0x0000, 0, 0},
  {0x0704, 0x0000, 0, 0},
  {0x0340, 0x18D0, 0, 0},
  {0x0202, 0x0C26, 0, 0},
  {0x0204, 0x01AD, 0, 0},
  {0x020E, 0x0100, 0, 0},
  {0x0104, 0x0001, 0, 0},
 };

static const struct cam_sensor_i2c_reg_setting hp2_fll_settings[] = {
	{ hp2_fll_setting, ARRAY_SIZE(hp2_fll_setting),
	  CAMERA_SENSOR_I2C_TYPE_WORD, CAMERA_SENSOR_I2C_TYPE_WORD, 0 },
};

static struct cam_sensor_i2c_reg_array hp2_streamoff_setting[] = {
  {0xFCFC, 0x4000, 0, 0},
  {0x0E00, 0x0080, 0, 0},
  {0x0100, 0x0003, 0, 0},
 };

static const struct cam_sensor_i2c_reg_setting hp2_streamoff_settings[] = {
	{ hp2_streamoff_setting, ARRAY_SIZE(hp2_streamoff_setting),
	  CAMERA_SENSOR_I2C_TYPE_WORD, CAMERA_SENSOR_I2C_TYPE_WORD, 0 },
};

static struct cam_sensor_i2c_reg_array hp2_streamon_setting[] = {
  {0x6028, 0x1002, 0, 0},
  {0x602A, 0xCEB4, 0, 0},
  {0x6F12, 0x0000, 0, 0},
  {0x0100, 0x0103, 0, 0},
 };

static const struct cam_sensor_i2c_reg_setting hp2_streamon_settings[] = {
	{ hp2_streamon_setting, ARRAY_SIZE(hp2_streamon_setting),
	  CAMERA_SENSOR_I2C_TYPE_WORD, CAMERA_SENSOR_I2C_TYPE_WORD, 0 },
};

static struct cam_sensor_i2c_reg_array s5k2ld_fll_setting[] = {
  {0x0104, 0x0101, 0, 0},
  {0x0702, 0x0000, 0, 0},
  {0x0704, 0x0000, 0, 0},
  {0x0340, 0x2F8E, 0, 0},
  {0x0202, 0x0D11, 0, 0},
  {0x0204, 0x0063, 0, 0},
  {0x020E, 0x0100, 0, 0},
  {0x0104, 0x0001, 0, 0},
 };

static const struct cam_sensor_i2c_reg_setting s5k2ld_fll_settings[] = {
	{ s5k2ld_fll_setting, ARRAY_SIZE(s5k2ld_fll_setting),
	  CAMERA_SENSOR_I2C_TYPE_WORD, CAMERA_SENSOR_I2C_TYPE_WORD, 0 },
};

static struct cam_sensor_i2c_reg_array s5k2ld_streamoff_setting[] = {
  {0x0E0A, 0x0000, 0, 0},
  {0x0100, 0x0000, 0, 0},
 };

static const struct cam_sensor_i2c_reg_setting s5k2ld_streamoff_settings[] = {
	{ s5k2ld_streamoff_setting, ARRAY_SIZE(s5k2ld_streamoff_setting),
	  CAMERA_SENSOR_I2C_TYPE_WORD, CAMERA_SENSOR_I2C_TYPE_WORD, 0 },
};

static struct cam_sensor_i2c_reg_array s5k2ld_streamon_setting[] = {
  {0x0100, 0x0100, 0, 0},
 };

static const struct cam_sensor_i2c_reg_setting s5k2ld_streamon_settings[] = {
	{ s5k2ld_streamon_setting, ARRAY_SIZE(s5k2ld_streamon_setting),
	  CAMERA_SENSOR_I2C_TYPE_WORD, CAMERA_SENSOR_I2C_TYPE_WORD, 0 },
};

struct cam_hyperlapse_profile {
	const struct cam_sensor_i2c_reg_setting *fll, *streamoff, *streamon;
};

static const struct cam_hyperlapse_profile gn3_hyperlapse = {
	gn3_fll_settings, gn3_streamoff_settings, gn3_streamon_settings,
};

static const struct cam_hyperlapse_profile hp2_hyperlapse = {
	hp2_fll_settings, hp2_streamoff_settings, hp2_streamon_settings,
};

static const struct cam_hyperlapse_profile s5k2ld_hyperlapse = {
	s5k2ld_fll_settings, s5k2ld_streamoff_settings, s5k2ld_streamon_settings,
};


#endif /* _CAM_SENSOR_HYPERLAPSE_H_ */
