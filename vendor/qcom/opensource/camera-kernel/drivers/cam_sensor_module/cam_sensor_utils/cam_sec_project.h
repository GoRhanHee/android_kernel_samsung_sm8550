/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _CAM_SEC_PROJECT_H_
#define _CAM_SEC_PROJECT_H_

#include <linux/kconfig.h>
#include <linux/of.h>
#include <linux/string.h>

enum cam_sec_project {
	CAM_SEC_PROJECT_UNKNOWN,
	CAM_SEC_PROJECT_DM1Q,
	CAM_SEC_PROJECT_DM2Q,
	CAM_SEC_PROJECT_DM3Q,
	CAM_SEC_PROJECT_Q5Q,
	CAM_SEC_PROJECT_B5Q,
};

static inline enum cam_sec_project cam_sec_get_project(void)
{
#if IS_ENABLED(CONFIG_SEC_UNIVERSAL_PROJECT)
	struct device_node *root;
	const char *model;
	enum cam_sec_project project = CAM_SEC_PROJECT_UNKNOWN;

	/* Samsung overlays identify the product in the root model property.
	 * The compatible strings identify kalama and are shared by all products.
	 */
	root = of_find_node_by_path("/");
	if (!root)
		return project;

	if (!of_property_read_string(root, "model", &model)) {
		if (strstr(model, "Samsung DM1Q PROJECT"))
			project = CAM_SEC_PROJECT_DM1Q;
		else if (strstr(model, "Samsung DM2Q PROJECT"))
			project = CAM_SEC_PROJECT_DM2Q;
		else if (strstr(model, "Samsung DM3Q PROJECT"))
			project = CAM_SEC_PROJECT_DM3Q;
		else if (strstr(model, "Samsung Q5Q PROJECT"))
			project = CAM_SEC_PROJECT_Q5Q;
		else if (strstr(model, "Samsung B5Q PROJECT"))
			project = CAM_SEC_PROJECT_B5Q;
	}
	of_node_put(root);
	return project;
#elif defined(CONFIG_SEC_DM1Q_PROJECT)
	return CAM_SEC_PROJECT_DM1Q;
#elif defined(CONFIG_SEC_DM2Q_PROJECT)
	return CAM_SEC_PROJECT_DM2Q;
#elif defined(CONFIG_SEC_DM3Q_PROJECT)
	return CAM_SEC_PROJECT_DM3Q;
#elif defined(CONFIG_SEC_Q5Q_PROJECT)
	return CAM_SEC_PROJECT_Q5Q;
#elif defined(CONFIG_SEC_B5Q_PROJECT)
	return CAM_SEC_PROJECT_B5Q;
#else
	return CAM_SEC_PROJECT_UNKNOWN;
#endif
}

#endif /* _CAM_SEC_PROJECT_H_ */
