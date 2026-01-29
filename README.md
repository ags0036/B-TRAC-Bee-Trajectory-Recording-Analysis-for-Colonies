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

## File Structure

BTRAC_GUI.m - The main application with GUI controls, session management, and workflow orchestration
processVideoSession.m - The core computer vision engine that handles bee detection, tracking, and bearing calculations
createMapVisualization.m - Creates GPS maps with bearing arrows and hive location markers

### User Guide:
Here is the User interface of B-TRAC:
![User Interface]([https://github.com/adam-p/markdown-here/raw/master/src/common/images/icon48.png "Logo Title Text 1"](https://github.com/lm0116/B-TRAC-Bee-Trajectory-Recording-Analysis-for-Colonies/blob/main/GUI%20First%20Iteration%20Picture.png?raw=true
))

Step 1: Add Observation Sessions

1. Click **"+ Add New Session"**
2. Fill in session details:
   - **Session Name:** Descriptive name 
   - **Video File:** Click "Browse" to select video file
   - **GPS Coordinates:**
     - Enter Latitude and Longitude manually, OR
     - Click "Browse" to load GPS file from Garmin
   - **Date:** Recording date
   - **Notes:** Optional notes about session

3. Click **"Add Session"**
4. Repeat for all observation sessions

**Tip:** Add all sessions before processing for automatic triangulation.

Step 2: Configure Camera Settings

**Focal Length (pixels):**
- Default: 1000
- Adjust based on camera calibration
- Higher values = more zoom

**Compass Offset (degrees):**
- Camera heading relative to North
- 0° = Camera points North
- 90° = Camera points East
- 180° = Camera points South
- 270° = Camera points West

Step 3: Process Sessions

1. Verify all sessions are added correctly
2. Click **"Process All Sessions"**
3. Watch progress bar and status updates
4. Processing time: ~2-5 minutes per video

**What's Happening:**
- Video analysis and bee tracking
- Trajectory extraction
- Bearing calculation
- Statistical analysis
- Triangulation (if 2+ sessions)

Step 4: Review Results

**During Processing:**
- Live tracking visualization shows detected bees
- Yellow trails show bee trajectories
- Red dots indicate current positions

**Final Results:**
- GPS map with:
  - Blue circles = Observation points
  - Colored arrows = Average bearings
  - Yellow star = Estimated hive location
  - Dashed circles = Uncertainty estimates

**Color Coding:**
- Green = High confidence (>70%)
- Yellow = Medium confidence (40-70%)
- Red = Low confidence (<40%)

Step 5: Export Results

1. Click **"Export Results"**
2. Choose save location
3. Three files are created:
   - `results.mat` - Complete data (for MATLAB)
   - `results_map.png` - Map image
   - `results_summary.txt` - Text summary

6. Review Results

### Bearing Analysis for each trap

**Average Bearing:**
- Direction (0-360°) where most bees departed
- 0° = North, 90° = East, 180° = South, 270° = West

**Confidence Score:**
- 0-100% indicating reliability
- Higher = more consistent bee departures
- Based on:
  - Number of trajectories tracked
  - Consistency of departure angles
  - Statistical clustering

**Interpretation:**
- >80%: Excellent - bees show strong directional preference
- 60-80%: Good - clear pattern visible
- 40-60%: Fair - some scatter but usable
- <40%: Poor - consider recollecting data

### Hive Location Estimate

**Triangulation:**
- Calculated from 2 or more observation points
- More points = better accuracy
- Bearings should intersect at good angles (not parallel)

**Uncertainty Circle:**
- Shows approximate error range
- Typical accuracy: ±50-200 meters
- Affected by:
  - GPS accuracy
  - Bearing confidence
  - Geometric configuration
  - Number of observation points


### Compilation Guide:

**Required Software**
1. **MATLAB** 
2. **MATLAB Compiler** toolbox
3. **Required MATLAB Toolboxes:**
   - Computer Vision Toolbox
   - Image Processing Toolbox
   - Statistics and Machine Learning Toolbox
*** TODO: Once tested, add comments about using installer and running the executable
