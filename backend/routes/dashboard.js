const express = require('express');
const { Op, fn, col, literal } = require('sequelize');
const WasteLog = require('../models/WasteLog');
const Claim = require('../models/Claim');
const User = require('../models/User');
const { auth, requireRole } = require('../middleware/auth');
const axios = require('axios');
require('dotenv').config();

const router = express.Router();

// GET /api/dashboard/kitchen/stats
router.get('/kitchen/stats', auth, requireRole('kitchen'), async (req, res) => {
  try {
    const kitchenId = req.user.id;

    const totalLogged = await WasteLog.count({ where: { kitchenId } });
    const totalQuantity = await WasteLog.sum('quantity', { where: { kitchenId } }) || 0;
    const totalClaimed = await WasteLog.count({ where: { kitchenId, status: 'claimed' } });
    const totalCompleted = await WasteLog.count({ where: { kitchenId, status: 'completed' } });
    const totalPending = await WasteLog.count({ where: { kitchenId, status: 'pending' } });

    // Waste by food type
    const byType = await WasteLog.findAll({
      where: { kitchenId },
      attributes: ['foodType', [fn('SUM', col('quantity')), 'total']],
      group: ['foodType'],
      raw: true
    });

    res.json({
      totalLogged,
      totalQuantity: Math.round(totalQuantity * 100) / 100,
      totalClaimed,
      totalCompleted,
      totalPending,
      redistributedQuantity: Math.round((await WasteLog.sum('quantity', { where: { kitchenId, status: { [Op.in]: ['claimed', 'completed'] } } }) || 0) * 100) / 100,
      byType
    });
  } catch (err) {
    console.error('Kitchen stats error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

// GET /api/dashboard/kitchen/history — Last 30 days for charts
router.get('/kitchen/history', auth, requireRole('kitchen'), async (req, res) => {
  try {
    const days = parseInt(req.query.days) || 30;
    const since = new Date();
    since.setDate(since.getDate() - days);

    const logs = await WasteLog.findAll({
      where: {
        kitchenId: req.user.id,
        logDate: { [Op.gte]: since }
      },
      attributes: ['logDate', 'foodType', 'quantity', 'status'],
      order: [['logDate', 'ASC']],
      raw: true
    });

    // Aggregate by date
    const byDate = {};
    logs.forEach(log => {
      const date = log.logDate;
      if (!byDate[date]) byDate[date] = { date, total: 0, items: [] };
      byDate[date].total += log.quantity;
      byDate[date].items.push(log);
    });

    res.json(Object.values(byDate));
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

// GET /api/dashboard/ngo/stats
router.get('/ngo/stats', auth, requireRole('ngo'), async (req, res) => {
  try {
    const ngoId = req.user.id;
    const totalClaimed = await Claim.count({ where: { ngoId } });
    const totalCompleted = await Claim.count({ where: { ngoId, status: 'completed' } });

    // Total quantity saved
    const completedClaims = await Claim.findAll({
      where: { ngoId, status: 'completed' },
      include: [{ model: WasteLog, as: 'wasteLog', attributes: ['quantity'] }]
    });
    const totalQuantitySaved = completedClaims.reduce((sum, c) => sum + (c.wasteLog?.quantity || 0), 0);

    res.json({
      totalClaimed,
      totalCompleted,
      totalQuantitySaved: Math.round(totalQuantitySaved * 100) / 100
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

// GET /api/dashboard/predictions — Fetch from ML service
router.get('/predictions', auth, async (req, res) => {
  try {
    const days = req.query.days || 7;
    const response = await axios.get(`${process.env.ML_SERVICE_URL}/predict?days=${days}`);
    res.json(response.data);
  } catch (err) {
    // If ML service is down, return mock predictions
    console.warn('ML service unavailable, returning mock predictions');
    const mockPredictions = generateMockPredictions(parseInt(req.query.days) || 7);
    res.json(mockPredictions);
  }
});

// Fallback mock predictions
function generateMockPredictions(days) {
  const foodTypes = ['rice', 'dal', 'roti', 'vegetables', 'curry'];
  const predictions = [];
  const today = new Date();

  for (let i = 1; i <= days; i++) {
    const date = new Date(today);
    date.setDate(date.getDate() + i);
    const dayOfWeek = date.getDay();
    const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

    const dayPrediction = {
      date: date.toISOString().split('T')[0],
      dayOfWeek: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][dayOfWeek],
      isWeekend,
      predictions: {}
    };

    foodTypes.forEach(type => {
      const base = type === 'rice' ? 8 : type === 'roti' ? 6 : 4;
      const weekendFactor = isWeekend ? 1.3 : 1;
      const noise = (Math.random() - 0.5) * 2;
      dayPrediction.predictions[type] = Math.round((base * weekendFactor + noise) * 10) / 10;
    });

    predictions.push(dayPrediction);
  }

  return { predictions, model: 'mock', accuracy: 0.82 };
}

module.exports = router;
