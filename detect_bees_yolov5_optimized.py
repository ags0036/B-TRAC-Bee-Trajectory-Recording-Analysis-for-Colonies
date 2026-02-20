import sys
import torch
import numpy as np
from pathlib import Path

model_path = sys.argv[1]
image_path = sys.argv[2]

# Load model once and cache (using global would be better but this is simpler)
model = torch.hub.load('ultralytics/yolov5', 'custom', path=model_path, force_reload=False)
model.conf = 0.25  # NMS confidence threshold
model.iou = 0.45   # NMS IoU threshold

# Set to eval mode and optimize
model.eval()
if torch.cuda.is_available():
    model = model.cuda()
    
# Disable gradient computation for speed
torch.set_grad_enabled(False)

# Run inference with reduced image size for speed
results = model(image_path, size=640)  # Can reduce to 416 for even more speed

# Extract detections (xyxy format)
detections = results.xyxy[0].cpu().numpy()

if len(detections) > 0:
    boxes = detections[:, :4]  # x1, y1, x2, y2
    scores = detections[:, 4]  # confidence scores
    
    # Save results (using faster numpy format)
    np.savetxt("detections_boxes.txt", boxes, delimiter=",", fmt='%.2f')
    np.savetxt("detections_scores.txt", scores, fmt='%.4f')
    
    print(f"DETECTED:{len(boxes)}")
else:
    # Create empty files
    np.savetxt("detections_boxes.txt", np.array([]))
    np.savetxt("detections_scores.txt", np.array([]))
    print("DETECTED:0")
