const express = require('express');
const { Op } = require('sequelize');
const WasteLog = require('../models/WasteLog');
const User = require('../models/User');
const { auth, requireRole } = require('../middleware/auth');
const { findNearbyNGOs } = require('../utils/matcher');
const axios = require('axios');

const router = express.Router();

// POST /api/waste/parse — Smart AI Parsing for Log Food
router.post('/parse', auth, requireRole('kitchen'), async (req, res) => {
  try {
    const { text } = req.body;
    if (!text) return res.status(400).json({ error: 'Text required' });

    const prompt = `
      You are an AI assistant parsing food waste logs for a commercial kitchen.
      Extract the following from this text: "${text}"
      Return ONLY a raw JSON object with no markdown formatting.
      Format:
      {
        "foodType": "rice|dal|roti|vegetables|curry|biryani|bread|fruits|dairy|other",
        "otherFoodType": "name of food if 'other' is selected (else empty string)",
        "quantity": <number in kg>,
        "notes": "any extra context"
      }
    `;

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) throw new Error("Gemini API key missing");

    const response = await axios.post(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`,
      {
        contents: [{ parts: [{ text: prompt }] }]
      },
      { headers: { 'Content-Type': 'application/json' } }
    );

    let jsonString = response.data.candidates[0].content.parts[0].text;
    jsonString = jsonString.replace(/```json/g, '').replace(/```/g, '').trim();
    const parsedData = JSON.parse(jsonString);

    res.json(parsedData);
  } catch (err) {
    console.error('NLP Parse Error:', err.response?.data || err.message);
    res.status(500).json({ error: 'Failed to parse text' });
  }
});

// POST /api/waste/pos-sync — Mock POS Integration (Phase 2 Hackathon Demo)
router.post('/pos-sync', auth, requireRole('kitchen'), async (req, res) => {
  try {
    const { items, timestamp } = req.body;
    if (!items || !Array.isArray(items)) {
      return res.status(400).json({ error: 'Invalid POS data payload' });
    }
    
    // Simulate processing delay for realistic demo
    await new Promise(resolve => setTimeout(resolve, 500));
    
    res.json({
      success: true,
      message: `Successfully synced ${items.length} POS records to inventory database.`,
      syncedAt: timestamp || new Date().toISOString()
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to sync POS data' });
  }
});

// POST /api/waste/log — Kitchen logs surplus food
router.post('/log', auth, requireRole('kitchen'), async (req, res) => {
  try {
    const { foodType, quantity, unit, notes } = req.body;

    const log = await WasteLog.create({
      kitchenId: req.user.id,
      foodType,
      quantity,
      unit: unit || 'kg',
      notes,
      logDate: new Date()
    });

    // Find nearby NGOs for notification
    const kitchen = await User.findByPk(req.user.id);
    let matchedNGOs = [];
    if (kitchen.latitude && kitchen.longitude) {
      matchedNGOs = await findNearbyNGOs(kitchen.latitude, kitchen.longitude, 10);
    }

    res.status(201).json({
      log,
      matchedNGOs,
      message: `Food logged! ${matchedNGOs.length} NGOs notified nearby.`
    });
  } catch (err) {
    console.error('Log waste error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

// GET /api/waste/my-logs — Kitchen's own logs
router.get('/my-logs', auth, requireRole('kitchen'), async (req, res) => {
  try {
    const logs = await WasteLog.findAll({
      where: { kitchenId: req.user.id },
      include: [{ model: User, as: 'claimer', attributes: ['name', 'organization'] }],
      order: [['createdAt', 'DESC']]
    });
    res.json(logs);
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

// GET /api/waste/available — All pending food for NGOs
router.get('/available', auth, requireRole('ngo'), async (req, res) => {
  try {
    const ngo = await User.findByPk(req.user.id);
    const logs = await WasteLog.findAll({
      where: { status: 'pending' },
      include: [{ model: User, as: 'kitchen', attributes: ['id', 'name', 'organization', 'address', 'latitude', 'longitude', 'phone'] }],
      order: [['createdAt', 'DESC']]
    });

    // Add distance info if NGO has location
    const result = logs.map(log => {
      const plain = log.toJSON();
      if (ngo.latitude && ngo.longitude && plain.kitchen.latitude && plain.kitchen.longitude) {
        const { haversine } = require('../utils/haversine');
        plain.distance = Math.round(haversine(ngo.latitude, ngo.longitude, plain.kitchen.latitude, plain.kitchen.longitude) * 100) / 100;
      }
      return plain;
    });

    // Sort by distance if available
    result.sort((a, b) => (a.distance || 999) - (b.distance || 999));

    res.json(result);
  } catch (err) {
    console.error('Available waste error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

// PATCH /api/waste/:id/status — Update waste log status
router.patch('/:id/status', auth, async (req, res) => {
  try {
    const { status } = req.body;
    const log = await WasteLog.findByPk(req.params.id);
    if (!log) return res.status(404).json({ error: 'Log not found' });

    log.status = status;
    await log.save();
    res.json(log);
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;
