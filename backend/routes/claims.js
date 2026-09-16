const express = require('express');
const Claim = require('../models/Claim');
const WasteLog = require('../models/WasteLog');
const User = require('../models/User');
const { auth, requireRole } = require('../middleware/auth');

const router = express.Router();

// POST /api/claims/:wasteId/claim — NGO claims food
router.post('/:wasteId/claim', auth, requireRole('ngo'), async (req, res) => {
  try {
    const log = await WasteLog.findByPk(req.params.wasteId);
    if (!log) return res.status(404).json({ error: 'Waste log not found' });
    if (log.status !== 'pending') return res.status(400).json({ error: 'This food is no longer available' });

    // Update waste log
    log.status = 'claimed';
    log.claimedBy = req.user.id;
    log.claimedAt = new Date();
    await log.save();

    // Create claim record
    const claim = await Claim.create({
      wasteLogId: log.id,
      ngoId: req.user.id,
      kitchenId: log.kitchenId,
      status: 'claimed'
    });

    res.status(201).json({ claim, message: 'Food claimed successfully!' });
  } catch (err) {
    console.error('Claim error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

// PATCH /api/claims/:id/complete — Mark as picked up
router.patch('/:id/complete', auth, requireRole('ngo'), async (req, res) => {
  try {
    const claim = await Claim.findByPk(req.params.id);
    if (!claim) return res.status(404).json({ error: 'Claim not found' });

    claim.status = 'completed';
    claim.completedAt = new Date();
    await claim.save();

    // Also update waste log
    const log = await WasteLog.findByPk(claim.wasteLogId);
    if (log) {
      log.status = 'completed';
      await log.save();
    }

    res.json({ claim, message: 'Pickup completed!' });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

// GET /api/claims/my-claims — NGO's claims
router.get('/my-claims', auth, requireRole('ngo'), async (req, res) => {
  try {
    const claims = await Claim.findAll({
      where: { ngoId: req.user.id },
      include: [
        { model: WasteLog, as: 'wasteLog' },
        { model: User, as: 'kitchen', attributes: ['name', 'organization', 'address', 'latitude', 'longitude', 'phone'] }
      ],
      order: [['claimedAt', 'DESC']]
    });
    res.json(claims);
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

// GET /api/claims/kitchen-claims — Claims against kitchen's logs
router.get('/kitchen-claims', auth, requireRole('kitchen'), async (req, res) => {
  try {
    const claims = await Claim.findAll({
      where: { kitchenId: req.user.id },
      include: [
        { model: WasteLog, as: 'wasteLog' },
        { model: User, as: 'ngo', attributes: ['name', 'organization', 'phone'] }
      ],
      order: [['claimedAt', 'DESC']]
    });
    res.json(claims);
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;
