# B-TRAC-Bee-Trajectory-Recording-Analysis-for-Colonies
This repository contains the software implementation for B-TRAC, an automated system for extracting honey bee flight trajectories from video and estimating hive locations using directional bearings and GPS data.


The codebase follows a modular video-to-geolocation processing pipeline. Raw video captured from a calibrated, fixed-geometry camera is first preprocessed to compensate for lens distortion and stabilize the scene. Background subtraction and motion-based filtering are then applied to isolate moving objects in outdoor environments with clutter, changing lighting, and foliage motion. Candidate bee detections are tracked frame-to-frame using lightweight object tracking logic to form short flight trajectories during takeoff.

From each valid trajectory, a departure angle is computed relative to the camera’s calibrated reference frame. Individual bearings are aggregated across many detected bees, and statistical averaging is used to reduce noise and outliers caused by turbulence, tracking error, or anomalous flight paths. This produces a dominant bearing that represents the most likely direction of the hive from a given feeder location.

The software supports combining multiple recording sessions taken at different GPS-tagged feeder positions. Bearings from each location are projected onto a geographic coordinate system, and intersection analysis is used to estimate candidate hive locations. Results are visualized on GPS-based maps to support field validation and iterative data collection.

Overall, the code emphasizes robustness to outdoor conditions, clear separation between processing stages, and extensibility for future improvements in detection accuracy, mapping, or hardware integration.
