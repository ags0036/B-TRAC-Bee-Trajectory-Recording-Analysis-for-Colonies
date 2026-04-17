# B-TRAC-Bee-Trajectory-Recording-Analysis-for-Colonies
This repository contains the software implementation for B-TRAC, an automated system for extracting honey bee flight trajectories from video and estimating hive locations using directional bearings and GPS data.


The codebase follows a modular video-to-geolocation processing pipeline. Raw video captured from a calibrated, fixed-geometry camera is first preprocessed to compensate for lens distortion and stabilize the scene. Background subtraction and motion-based filtering are then applied to isolate moving objects in outdoor environments with clutter, changing lighting, and foliage motion. Candidate bee detections are tracked frame-to-frame using lightweight object tracking logic to form short flight trajectories during takeoff.

From each valid trajectory, a departure angle is computed relative to the camera’s calibrated reference frame. Individual bearings are aggregated across many detected bees, and statistical averaging is used to reduce noise and outliers. This produces a dominant bearing that represents the most likely direction of the hive from a given feeder location.

The software supports combining multiple recording sessions taken at different GPS-tagged feeder positions. Bearings from each location are projected onto a geographic coordinate system, and intersection analysis is used to estimate candidate hive locations. Results are visualized on GPS-based maps to support field validation and iterative data collection.

### Objectives

This MATLAB codebase implements an automated system for tracking honey bee flight trajectories from video data and triangulating wild hive locations. The system processes video from multiple observation points to:

1. Track individual bee trajectories using computer vision
2. Calculate departure bearings with statistical analysis
3. Triangulate hive locations from multiple observation points
4. Visualize results on GPS-based maps

### User's Manual 
Please refer to the Guide below for a system and software outline

https://docs.google.com/document/d/1KPP2rXnb4UvYPogX0u7hKUG5933_F7JgSibBqRx4bSU/edit?usp=sharing

