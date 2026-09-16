const User = require('../models/User');
const { haversine } = require('./haversine');

/**
 * Find NGOs within a given radius of a kitchen's location.
 * @param {number} kitchenLat - Kitchen latitude
 * @param {number} kitchenLng - Kitchen longitude
 * @param {number} radiusKm - Search radius in km (default: 10)
 * @returns {Array} Matched NGOs sorted by distance
 */
async function findNearbyNGOs(kitchenLat, kitchenLng, radiusKm = 10) {
  // Get all NGOs with location data
  const ngos = await User.findAll({
    where: { role: 'ngo' },
    attributes: ['id', 'name', 'email', 'organization', 'phone', 'address', 'latitude', 'longitude']
  });

  // Calculate distance, assign match score, and filter within radius
  const matched = ngos
    .map(ngo => {
      const dist = haversine(kitchenLat, kitchenLng, ngo.latitude, ngo.longitude);
      const safeDist = Math.max(dist, 0.1);
      
      // Mocking historical acceptance & urgency for prototype
      const historicalAcceptance = Math.random() * 0.4 + 0.6; // 0.6 to 1.0
      const urgencyMultiplier = Math.random() * 0.5 + 1.0; // 1.0 to 1.5
      
      const score = (1 / safeDist) * historicalAcceptance * urgencyMultiplier;

      return {
        id: ngo.id,
        name: ngo.name,
        email: ngo.email,
        organization: ngo.organization,
        phone: ngo.phone,
        address: ngo.address,
        latitude: ngo.latitude,
        longitude: ngo.longitude,
        distance: Math.round(dist * 100) / 100, // round to 2 decimals
        matchScore: Math.round(score * 100) / 100
      };
    })
    .filter(ngo => ngo.distance <= radiusKm)
    .sort((a, b) => b.matchScore - a.matchScore)
    .slice(0, 3); // Phase 3: limit to top 3 matches

  return matched;
}

module.exports = { findNearbyNGOs };
