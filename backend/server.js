const express = require('express');
const cors = require('cors');
const path = require('path');
require('dotenv').config();

const sequelize = require('./config/db');

// Import models (to register them)
const User = require('./models/User');
const WasteLog = require('./models/WasteLog');
const Claim = require('./models/Claim');

// Import routes
const authRoutes = require('./routes/auth');
const wasteRoutes = require('./routes/waste');
const claimRoutes = require('./routes/claims');
const dashboardRoutes = require('./routes/dashboard');

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Serve frontend static files
app.use(express.static(path.join(__dirname, '..', 'frontend')));

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/waste', wasteRoutes);
app.use('/api/claims', claimRoutes);
app.use('/api/dashboard', dashboardRoutes);

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Frontend config (exposes public keys)
app.get('/api/config', (req, res) => {
  res.json({
    googleMapsApiKey: process.env.GOOGLE_MAPS_API_KEY || ''
  });
});

// Catch-all: serve frontend (Express 5 compatible)
app.use((req, res, next) => {
  if (!req.path.startsWith('/api') && req.method === 'GET') {
    res.sendFile(path.join(__dirname, '..', 'frontend', 'index.html'));
  } else {
    next();
  }
});

const PORT = process.env.PORT || 5000;

// Start server
async function start() {
  try {
    await sequelize.authenticate();
    console.log('✅ PostgreSQL connected');

    // Sync models (create tables if not exist)
    await sequelize.sync({ alter: true });
    console.log('✅ Database synced');

    app.listen(PORT, () => {
      console.log(`🚀 Server running on http://localhost:${PORT}`);
      console.log(`📱 Frontend at http://localhost:${PORT}`);
    });
  } catch (err) {
    console.error('❌ Unable to start server:', err);
    process.exit(1);
  }
}

start();
