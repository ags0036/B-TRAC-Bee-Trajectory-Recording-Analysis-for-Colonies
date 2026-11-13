"""
bee_tracker_btrac.py
====================
B-TRAC Video Detection Bridge — YOLOv8 (.pt) model

Loads the model ONCE, streams the entire video, and writes a single
CSV that processVideo.m reads after this script finishes.
USAGE (called by processVideo.m automatically):
  python bee_tracker_btrac.py  <model.pt>  <video_file>
                               [--conf 0.35]
                               [--imgsz 1280]
                               [--every_n 1]
                               [--class_id 0]
                               [--output btrac_detections.csv]
"""

import sys
import argparse
import csv
import io
from pathlib import Path
import torch

# Check for GPU
if torch.cuda.is_available():
    device = 0
    print(f"Using GPU: {torch.cuda.get_device_name(0)}")
else:
    device = "cpu"
    print("No CUDA GPU available. Using CPU.")

# Force UTF-8 on Windows consoles
if hasattr(sys.stdout, 'buffer'):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'buffer'):
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

import cv2
import numpy as np

try:
    from ultralytics import YOLO
except ImportError:
    sys.exit(
        "[ERROR] ultralytics not installed.\n"
        "  Run:  pip install ultralytics"
    )


# ============================================================================
#  CLI
# ============================================================================
def parse_args():
    p = argparse.ArgumentParser(
        description="B-TRAC detection bridge: whole-video YOLO inference → CSV"
    )
    p.add_argument("model",   help="Path to best.pt (YOLOv8 weights)")
    p.add_argument("video",   help="Path to input video file")
    p.add_argument("--conf",      type=float, default=0.35,
                   help="Confidence threshold (default: 0.35)")
    p.add_argument("--imgsz",     type=int,   default=1280,
                   help="Inference image size (default: 1280 — better for small/distant bees)")
    p.add_argument("--every_n",   type=int,   default=1,
                   help="Process every N-th frame (default: 1 = every frame)")
    p.add_argument("--class_id",  type=int,   default=0,
                   help="YOLO class index for bees (default: 0)")
    p.add_argument("--output",    default="btrac_detections.csv",
                   help="Output CSV path (default: btrac_detections.csv)")
    return p.parse_args()


# ============================================================================
#  MAIN
# ============================================================================
def main():
    args = parse_args()

    # ── Validate & load model (loaded ONCE — key improvement over old approach) ──
    model_path = Path(args.model)
    if not model_path.exists():
        sys.exit(f"[ERROR] Model not found: {model_path.resolve()}")

    print(f"[B-TRAC] Loading model : {model_path}")
    model = YOLO(str(model_path))
    print(f"[B-TRAC] Model loaded.")

    # ── Open video ──────────────────────────────────────────────────────────────
    video_path = Path(args.video)
    if not video_path.exists():
        sys.exit(f"[ERROR] Video not found: {video_path.resolve()}")

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        sys.exit(f"[ERROR] Could not open video: {video_path}")

    n_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps      = cap.get(cv2.CAP_PROP_FPS)
    width    = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height   = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    print(f"[B-TRAC] Video : {video_path.name}")
    print(f"[B-TRAC] Size  : {width}x{height} @ {fps:.2f}fps | ~{n_frames} frames")
    print(f"[B-TRAC] Conf  : {args.conf}  |  imgsz: {args.imgsz}  |  every_n: {args.every_n}")

    fieldnames = ["frame", "x1", "y1", "x2", "y2", "cx", "cy", "confidence"]
    out_path = Path(args.output)

    # ── Open CSV immediately so MATLAB can start polling it ──────────────
    with open(out_path, "w", newline="") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        csv_file.flush()          # header visible to MATLAB right away

        frame_idx  = 0
        proc_idx   = 0
        total_dets = 0

        print(f"[B-TRAC] Processing video ...\n")

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            frame_idx += 1
            if (frame_idx - 1) % args.every_n != 0:
                continue
            proc_idx += 1

            results = model.predict(
                source=frame,
                conf=args.conf,
                iou=0.45,
                imgsz=args.imgsz,
                classes=[args.class_id],
                verbose=False,
                device=device
            )

            result = results[0]
            boxes  = result.boxes.xyxy.cpu().numpy()
            scores = result.boxes.conf.cpu().numpy()

            for i in range(len(boxes)):
                x1, y1, x2, y2 = boxes[i]
                cx = (x1 + x2) / 2.0
                cy = (y1 + y2) / 2.0
                writer.writerow({
                    "frame":      frame_idx,
                    "x1":         round(float(x1), 2),
                    "y1":         round(float(y1), 2),
                    "x2":         round(float(x2), 2),
                    "y2":         round(float(y2), 2),
                    "cx":         round(float(cx), 2),
                    "cy":         round(float(cy), 2),
                    "confidence": round(float(scores[i]), 4),
                })
                total_dets += 1

            # ── Flush every frame so MATLAB sees rows immediately ──────
            csv_file.flush()

            if proc_idx % 50 == 0:
                print(f"  frame {frame_idx:5d} / {n_frames}  |  "
                      f"dets this frame: {len(boxes)}  |  total: {total_dets}")

        cap.release()

    print(f"\n[B-TRAC] Complete — {total_dets} detections across {proc_idx} processed frames")
    print(f"[B-TRAC] Saved: {out_path}")
    print(f"BTRAC_DONE:{total_dets}")
    
if __name__ == "__main__":
    main()
