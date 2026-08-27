# Identification and Reduction of Noise by Mechanical Systems Onboard Ships

## Project Overview

This project addresses a critical challenge in maritime engineering: reducing mechanical noise to enhance stealth capabilities, improve sonar clarity, and protect crew health.

Instead of relying on expensive, heavy hardware solutions, this repository implements a software-defined AI system capable of real-time diagnostics and signal purification. The system processes raw audio to detect, classify, and reduce mechanical noise with high precision.

### Key Results

* **Noise Reduction:** Achieved a 60% reduction in background mechanical noise.
* **Classification Accuracy:** **98% accuracy** in identifying specific noise sources (UUV, Speedboat, Kaiyuan).
* **Deployment:** Fully offline-capable web application for naval vessels.


## Technical Architecture: The 3-Stage Pipeline

The core of this project is a custom deep learning pipeline that processes 3-second audio clips through three distinct stages:

### 1. Detection (The Gatekeeper)

* **Model:** YAMNet
* **Function:** Acts as a highly efficient filter to continuously scan audio streams.
* **Purpose:** Determines if a target mechanical noise exists before triggering heavier downstream models, saving computational power.

### 2. Identification (The Classifier)

* **Model:** CRNN (Convolutional Recurrent Neural Network)
* **Function:** Classifies the detected noise into specific categories.
* **Classes:** Speedboat, UUV (Unmanned Underwater Vehicle), Kaiyuan.
* **Performance:** 98% Accuracy.

### 3. Reduction (The Denoiser) 

* **Model:** TasNet (Time-domain Audio Separation Network)
* **Function:** A lightweight Convolutional Encoder-Decoder network designed to "scrub" background interference.
* **Training Details:** * Trained 3 separate models (one for each category).
* **Training Load:** 50 epochs per model, requiring ~14 hours of training time each.


## Dataset & Preprocessing

This project utilizes the QiandaoEar22 underwater acoustic dataset.

**Raw Data:** `.wav` files of 3-second duration.


* **Preprocessing Challenges:**
* Normalization of sample rates across the dataset.
* Splitting data into **"Target"** (pure signal) vs. **"Other"** (interference) for effective supervised learning.
* Conversion of raw audio into **Log Mel Spectrograms** for feature extraction.


## Tech Stack

* **Deep Learning:** Python, TensorFlow/Keras, PyTorch (YAMNet, CRNN, TasNet)
* **Backend:** Flask (Python) - Handles API requests and model inference.
* **Database:** SQLite - Used for local, offline-capable logging of detection timestamps and confidence scores.
* **Frontend:** HTML/JavaScript - Provides real-time visualization of signal analysis.


## Additional Resources

* **LinkedIn Article:** [Deep Dive into the 3-Stage Pipeline](https://lnkd.in/dapZbFSj)
* **Project Documentation:** See the `docs/` folder for detailed architecture diagrams and confusion matrices.

---

## Usage

1. **Clone the repository:**
```bash
git clone https://github.com/shahbazfdev/FYP.git

```


2. **Install dependencies:**
```bash
pip install -r requirements.txt

```


3. **Run the Flask App:**
```bash
python app.py

```


4. Access the dashboard at `http://localhost:5000` to start real-time detection.

