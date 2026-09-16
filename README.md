# 🍽️ SoulServe

> **"Serving Souls by Feeding Communities"**

SoulServe is an intelligent, full-stack web application designed to bridge the gap between commercial food surplus (restaurants, hotels, events) and local NGOs. By combining **Machine Learning forecasting**, **Generative AI NLP parsing**, and **Geospatial routing**, SoulServe aims to eradicate food waste while providing nutritious meals to those in need.

---

## ✨ Key Features & "Wow Factors"

### 1. 🤖 AI Smart Prep Sheet (Waste Prevention)
Instead of just reacting to waste, SoulServe prevents it. A Python microservice running a **Scikit-Learn Random Forest Regressor** analyzes historical waste patterns, weekday trends, and mock POS data to generate a daily predictive "Smart Prep Sheet" for kitchens, advising them to reduce specific ingredients before they are cooked.

### 2. ⚡ Frictionless NLP Logging (Gemini AI)
Kitchen staff are too busy to fill out complex forms. SoulServe uses the **Google Gemini API** for "Smart Auto-Fill". Staff can type a natural sentence like *"10kg leftover paneer biryani from the buffet"*, and the AI instantly extracts the food type, weight, and notes into structured data.

### 3. 📍 Intelligent Algorithmic Matching
When surplus food is logged, the Node.js backend uses the **Haversine formula** to calculate distances to nearby NGOs. It applies a weighted scoring algorithm `(1 / Distance) * Capacity * Urgency` to alert *only the Top 3 most capable NGOs*, preventing notification spam and ensuring rapid pickup.

### 4. 📋 Digital Food Safety Compliance
To protect restaurants from liability, the platform enforces a mandatory digital self-attestation checklist. Kitchen managers must verify food-grade containers and safe temperatures before the system allows the food to be logged and matched.

---

## 🛠️ Technologies Used

### Frontend (Client-Side)
*   **HTML5, CSS3, & Vanilla JS:** Extremely lightweight and fast, featuring native CSS variables for seamless Light/Dark mode toggling.
*   **Chart.js:** Real-time data visualization for waste trends and AI forecasts.
*   **Leaflet.js & OpenStreetMap:** Interactive mapping for NGO routing.

### Backend (Server-Side)
*   **Node.js & Express.js:** Fast, asynchronous event-driven REST API.
*   **PostgreSQL & Sequelize ORM:** Secure, relational database handling Users, Waste Logs, and Claims.

### Artificial Intelligence & Data Science
*   **Python & Flask:** Decoupled microservice for heavy computations.
*   **Scikit-Learn:** Random Forest Regressor model for time-series demand forecasting.
*   **Google Gemini API:** Generative AI for Natural Language Processing (NLP).

---

## 🚀 How to Run Locally

### Prerequisites
*   Node.js (v16+)
*   Python (3.9+)
*   PostgreSQL
*   A Google Gemini API Key

### 1. Database Setup
Ensure PostgreSQL is running on your machine. Create a database (e.g., `catch_me_db`).

### 2. Backend Setup
```bash
cd backend
npm install
```
Create a `.env` file in the `backend` directory:
```env
DB_NAME=catch_me_db
DB_USER=postgres
DB_PASSWORD=yourpassword
DB_HOST=localhost
JWT_SECRET=super_secret_key
PORT=5000
GEMINI_API_KEY=your_gemini_key_here
```
Run the backend server:
```bash
node server.js
```

### 3. ML Microservice Setup
Open a new terminal window:
```bash
cd ml-service
pip install -r requirements.txt
python app.py
```
*(The Flask ML server runs on port 5001).*

### 4. Frontend Access
Since the frontend uses static files and relative API calls, simply open your browser and navigate to:
```
http://localhost:5000/index.html
```

---

## 🤝 Project Methodology
1. **Predict:** AI analyzes data to generate a daily Prep Sheet, preventing surplus *before* it happens.
2. **Log:** Staff types a quick sentence; NLP instantly auto-fills the donation form.
3. **Verify:** Manager completes a mandatory digital checklist to ensure food safety compliance.
4. **Match:** Algorithm calculates proximity and urgency, alerting only the top 3 nearest NGOs.
5. **Claim:** NGO accepts the food and uses integrated maps for immediate pickup.
6. **Loop:** Completion data feeds back into the ML engine to improve tomorrow's predictions.

---
*Built with ❤️ for the Hackathon.*
