/* SPDX-License-Identifier: GPL-2.0-only */
/* Register sequences preserved from Samsung project-specific retention tables. */
#ifndef _CAM_SENSOR_RETENTION_H_
#define _CAM_SENSOR_RETENTION_H_

enum cam_retention_step {
	CAM_RETENTION_STREAM_ON,
	CAM_RETENTION_STREAM_OFF,
	CAM_RETENTION_ENABLE,
	CAM_RETENTION_PREPARE,
	CAM_RETENTION_HW_INIT,
	CAM_RETENTION_CHECKSUM,
	CAM_RETENTION_READY,
	CAM_RETENTION_STEP_COUNT,
};

struct cam_retention_profile {
	const struct cam_sensor_i2c_reg_setting *settings[CAM_RETENTION_STEP_COUNT];
	u32 count[CAM_RETENTION_STEP_COUNT];
};

static struct cam_sensor_i2c_reg_array gn3_stream_on_setting[] = {
 { 0x0100, 0x0103, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting gn3_stream_on_settings[] = {
 { gn3_stream_on_setting,
  ARRAY_SIZE(gn3_stream_on_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array gn3_stream_off_setting[] = {
 { 0x010E, 0x0100, 0x00, 0x00 },
 { 0x0100, 0x0003, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting gn3_stream_off_settings[] = {
 { gn3_stream_off_setting,
  ARRAY_SIZE(gn3_stream_off_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array gn3_retention_enable_setting[] = {
 { 0xFCFC, 0x4000, 0x00, 0x00 },
 { 0x6000, 0x0005, 0x00, 0x00 },
 { 0x010E, 0x0100, 0x00, 0x00 },
 { 0x19C2, 0x0000, 0x00, 0x00 },
 { 0x6000, 0x0085, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting gn3_retention_enable_settings[] = {
 { gn3_retention_enable_setting,
  ARRAY_SIZE(gn3_retention_enable_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array gn3_retention_prepare_setting[] = {
 { 0xFCFC, 0x4000, 0x00, 0x00 },
 { 0x6000, 0x0005, 0x00, 0x00 },
 { 0x19C4, 0x0000, 0x00, 0x00 },
 { 0x6000, 0x0085, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting gn3_retention_prepare_settings[] = {
 { gn3_retention_prepare_setting,
  ARRAY_SIZE(gn3_retention_prepare_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};

static const struct cam_retention_profile gn3_retention_profile = {
	.settings = {
		[CAM_RETENTION_STREAM_ON] = gn3_stream_on_settings,
		[CAM_RETENTION_STREAM_OFF] = gn3_stream_off_settings,
		[CAM_RETENTION_ENABLE] = gn3_retention_enable_settings,
		[CAM_RETENTION_PREPARE] = gn3_retention_prepare_settings,
	},
	.count = {
		[CAM_RETENTION_STREAM_ON] = ARRAY_SIZE(gn3_stream_on_settings),
		[CAM_RETENTION_STREAM_OFF] = ARRAY_SIZE(gn3_stream_off_settings),
		[CAM_RETENTION_ENABLE] = ARRAY_SIZE(gn3_retention_enable_settings),
		[CAM_RETENTION_PREPARE] = ARRAY_SIZE(gn3_retention_prepare_settings),
	},
};

static struct cam_sensor_i2c_reg_array hp2_stream_on_setting[] = {
 { 0x0100, 0x0103, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting hp2_stream_on_settings[] = {
 { hp2_stream_on_setting,
  ARRAY_SIZE(hp2_stream_on_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array hp2_stream_off_setting[] = {
 { 0xFCFC, 0x4000, 0x00, 0x00 },
 { 0x0100, 0x0003, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting hp2_stream_off_settings[] = {
 { hp2_stream_off_setting,
  ARRAY_SIZE(hp2_stream_off_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array hp2_retention_enable_setting[] = {
 { 0xFCFC, 0x4000, 0x00, 0x00 },
 { 0x0B30, 0x01FF, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting hp2_retention_enable_settings[] = {
 { hp2_retention_enable_setting,
  ARRAY_SIZE(hp2_retention_enable_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array hp2_retention_prepare1_setting[] = {
 { 0xFCFC, 0x4000, 0x00, 0x00 },
 { 0x6018, 0x0001, 0x01, 0x00 },
};
static struct cam_sensor_i2c_reg_array hp2_retention_prepare2_setting[] = {
 { 0x652A, 0x0001, 0x00, 0x00 },
 { 0x7096, 0x0001, 0x00, 0x00 },
 { 0x7002, 0x0008, 0x00, 0x00 },
 { 0x706E, 0x0D13, 0x00, 0x00 },
 { 0x6028, 0x1001, 0x00, 0x00 },
 { 0x602A, 0xC990, 0x00, 0x00 },
 { 0x6F12, 0x1002, 0x00, 0x00 },
 { 0x6F12, 0xF601, 0x00, 0x00 },
 { 0x6028, 0x1002, 0x00, 0x00 },
 { 0x602A, 0xC8C0, 0x00, 0x00 },
 { 0x6F12, 0xCAFE, 0x00, 0x00 },
 { 0x6F12, 0x1234, 0x00, 0x00 },
 { 0x6F12, 0xABBA, 0x00, 0x00 },
 { 0x6F12, 0x0345, 0x00, 0x00 },
 { 0x6014, 0x0001, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting hp2_retention_prepare_settings[] = {
 { hp2_retention_prepare1_setting,
  ARRAY_SIZE(hp2_retention_prepare1_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  5
 },
 { hp2_retention_prepare2_setting,
  ARRAY_SIZE(hp2_retention_prepare2_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  10
 },
};
static struct cam_sensor_i2c_reg_array hp2_retention_hw_init_setting[] = {
 { 0xFCFC, 0x4000, 0x00, 0x00 },
 { 0x6214, 0xE949, 0x00, 0x00 },
 { 0x6218, 0xE940, 0x00, 0x00 },
 { 0x6222, 0x0000, 0x00, 0x00 },
 { 0x621E, 0x00F0, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting hp2_retention_hw_init_settings[] = {
 { hp2_retention_hw_init_setting,
  ARRAY_SIZE(hp2_retention_hw_init_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array hp2_retention_checksum_setting[] = {
 { 0x602C, 0x1002, 0x01, 0x00 },
 { 0x602E, 0xF36C, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting hp2_retention_checksum_settings[] = {
 { hp2_retention_checksum_setting,
  ARRAY_SIZE(hp2_retention_checksum_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array hp2_retention_ready_setting[] = {
 { 0x602C, 0x1002, 0x00, 0x00 },
 { 0x602E, 0xF36E, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting hp2_retention_ready_settings[] = {
 { hp2_retention_ready_setting,
  ARRAY_SIZE(hp2_retention_ready_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};

static const struct cam_retention_profile hp2_retention_profile = {
	.settings = {
		[CAM_RETENTION_STREAM_ON] = hp2_stream_on_settings,
		[CAM_RETENTION_STREAM_OFF] = hp2_stream_off_settings,
		[CAM_RETENTION_ENABLE] = hp2_retention_enable_settings,
		[CAM_RETENTION_PREPARE] = hp2_retention_prepare_settings,
		[CAM_RETENTION_HW_INIT] = hp2_retention_hw_init_settings,
		[CAM_RETENTION_CHECKSUM] = hp2_retention_checksum_settings,
		[CAM_RETENTION_READY] = hp2_retention_ready_settings,
	},
	.count = {
		[CAM_RETENTION_STREAM_ON] = ARRAY_SIZE(hp2_stream_on_settings),
		[CAM_RETENTION_STREAM_OFF] = ARRAY_SIZE(hp2_stream_off_settings),
		[CAM_RETENTION_ENABLE] = ARRAY_SIZE(hp2_retention_enable_settings),
		[CAM_RETENTION_PREPARE] = ARRAY_SIZE(hp2_retention_prepare_settings),
		[CAM_RETENTION_HW_INIT] = ARRAY_SIZE(hp2_retention_hw_init_settings),
		[CAM_RETENTION_CHECKSUM] = ARRAY_SIZE(hp2_retention_checksum_settings),
		[CAM_RETENTION_READY] = ARRAY_SIZE(hp2_retention_ready_settings),
	},
};

static struct cam_sensor_i2c_reg_array s5k2ld_stream_on_setting[] = {
 { 0x0100, 0x0100, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting s5k2ld_stream_on_settings[] = {
 { s5k2ld_stream_on_setting,
  ARRAY_SIZE(s5k2ld_stream_on_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array s5k2ld_stream_off_setting[] = {
 { 0x0100, 0x0000, 0x00, 0x00 },
};

static const struct cam_sensor_i2c_reg_setting s5k2ld_stream_off_settings[] = {
 { s5k2ld_stream_off_setting,
  ARRAY_SIZE(s5k2ld_stream_off_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array s5k2ld_retention_enable_setting[] = {
 { 0x6028, 0x3000, 0x00, 0x00 },
 { 0x602A, 0x0484, 0x00, 0x00 },
 { 0x6F12, 0x0100, 0x00, 0x00 },
 { 0x010E, 0x0100, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting s5k2ld_retention_enable_settings[] = {
 { s5k2ld_retention_enable_setting,
  ARRAY_SIZE(s5k2ld_retention_enable_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};
static struct cam_sensor_i2c_reg_array s5k2ld_retention_prepare_setting[] = {
 { 0x6028, 0x3000, 0x00, 0x00 },
 { 0x602A, 0x0484, 0x00, 0x00 },
 { 0x6F12, 0x0100, 0x00, 0x00 },
 { 0x010E, 0x0100, 0x00, 0x00 },
 { 0x0BCC, 0x0000, 0x00, 0x00 },
};
static const struct cam_sensor_i2c_reg_setting s5k2ld_retention_prepare_settings[] = {
 { s5k2ld_retention_prepare_setting,
  ARRAY_SIZE(s5k2ld_retention_prepare_setting),
  CAMERA_SENSOR_I2C_TYPE_WORD,
  CAMERA_SENSOR_I2C_TYPE_WORD,
  0
 },
};

static const struct cam_retention_profile s5k2ld_retention_profile = {
	.settings = {
		[CAM_RETENTION_STREAM_ON] = s5k2ld_stream_on_settings,
		[CAM_RETENTION_STREAM_OFF] = s5k2ld_stream_off_settings,
		[CAM_RETENTION_ENABLE] = s5k2ld_retention_enable_settings,
		[CAM_RETENTION_PREPARE] = s5k2ld_retention_prepare_settings,
	},
	.count = {
		[CAM_RETENTION_STREAM_ON] = ARRAY_SIZE(s5k2ld_stream_on_settings),
		[CAM_RETENTION_STREAM_OFF] = ARRAY_SIZE(s5k2ld_stream_off_settings),
		[CAM_RETENTION_ENABLE] = ARRAY_SIZE(s5k2ld_retention_enable_settings),
		[CAM_RETENTION_PREPARE] = ARRAY_SIZE(s5k2ld_retention_prepare_settings),
	},
};

static inline const struct cam_retention_profile *cam_sensor_retention_profile(
	struct cam_sensor_ctrl_t *s_ctrl)
{
	switch (s_ctrl->sensordata->slave_info.sensor_id) {
	case SENSOR_ID_S5KGN3: return &gn3_retention_profile;
	case SENSOR_ID_S5KHP2: return &hp2_retention_profile;
	case SENSOR_ID_S5K2LD: return &s5k2ld_retention_profile;
	default: return NULL;
	}
}

static inline bool cam_sensor_has_retention(struct cam_sensor_ctrl_t *s_ctrl)
{
	return cam_sensor_retention_profile(s_ctrl) != NULL;
}

#endif /* _CAM_SENSOR_RETENTION_H_ */
