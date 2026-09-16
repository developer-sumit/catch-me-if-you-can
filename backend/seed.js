/**
 * Seed script: creates demo Kitchen + NGO users and some waste logs.
 * Run: node seed.js
 */
const bcrypt = require('bcryptjs');
require('dotenv').config();
const sequelize = require('./config/db');
const User = require('./models/User');
const WasteLog = require('./models/WasteLog');
const Claim = require('./models/Claim');

const FOOD_TYPES = ['rice', 'dal', 'roti', 'vegetables', 'curry', 'biryani', 'bread', 'fruits', 'dairy'];

async function seed() {
  try {
    await sequelize.authenticate();
    console.log('Connected to DB');

    // Force recreate tables
    await sequelize.sync({ force: true });
    console.log('Tables recreated');

    const hash = await bcrypt.hash('password123', 10);

    // Create Kitchen users (Delhi area)
    const kitchens = await User.bulkCreate([
      {
        name: 'Rajesh Kumar',
        email: 'kitchen1@demo.com',
        password: hash,
        role: 'kitchen',
        organization: 'Sharma Catering Services',
        phone: '9876543210',
        address: 'Connaught Place, New Delhi',
        latitude: 28.6315,
        longitude: 77.2167
      },
      {
        name: 'Priya Patel',
        email: 'kitchen2@demo.com',
        password: hash,
        role: 'kitchen',
        organization: 'Green Leaf Restaurant',
        phone: '9876543211',
        address: 'Karol Bagh, New Delhi',
        latitude: 28.6519,
        longitude: 77.1905
      },
      {
        name: 'Amit Singh',
        email: 'kitchen3@demo.com',
        password: hash,
        role: 'kitchen',
        organization: 'Royal Banquet Hall',
        phone: '9876543212',
        address: 'Dwarka, New Delhi',
        latitude: 28.5921,
        longitude: 77.0460
      }
    ]);

    // Create NGO users
    const ngos = await User.bulkCreate([
      {
        name: 'Sunita Devi',
        email: 'ngo1@demo.com',
        password: hash,
        role: 'ngo',
        organization: 'Feeding India Foundation',
        phone: '9876543220',
        address: 'Janpath, New Delhi',
        latitude: 28.6258,
        longitude: 77.2190
      },
      {
        name: 'Mohammed Ali',
        email: 'ngo2@demo.com',
        password: hash,
        role: 'ngo',
        organization: 'No Food Waste NGO',
        phone: '9876543221',
        address: 'Saket, New Delhi',
        latitude: 28.5244,
        longitude: 77.2066
      },
      {
        name: 'Deepa Sharma',
        email: 'ngo3@demo.com',
        password: hash,
        role: 'ngo',
        organization: 'Annapurna Trust',
        phone: '9876543222',
        address: 'Lajpat Nagar, New Delhi',
        latitude: 28.5700,
        longitude: 77.2373
      }
    ]);

    // Generate waste logs for last 30 days
    const logs = [];
    const today = new Date();
    for (let d = 30; d >= 0; d--) {
      const date = new Date(today);
      date.setDate(date.getDate() - d);
      const dayOfWeek = date.getDay();
      const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

      // Each kitchen logs 2-4 items per day
      for (const kitchen of kitchens) {
        const numItems = isWeekend ? 4 : 2 + Math.floor(Math.random() * 2);
        for (let i = 0; i < numItems; i++) {
          const foodType = FOOD_TYPES[Math.floor(Math.random() * FOOD_TYPES.length)];
          const baseQty = foodType === 'rice' ? 8 : foodType === 'roti' ? 6 : 4;
          const weekendMult = isWeekend ? 1.4 : 1;
          const quantity = Math.round((baseQty * weekendMult + (Math.random() - 0.5) * 3) * 10) / 10;

          // Older logs are completed, recent ones are pending
          let status = 'completed';
          if (d <= 2) status = 'pending';
          else if (d <= 5) status = Math.random() > 0.5 ? 'claimed' : 'completed';

          logs.push({
            kitchenId: kitchen.id,
            foodType,
            quantity: Math.max(0.5, quantity),
            unit: 'kg',
            status,
            claimedBy: status !== 'pending' ? ngos[Math.floor(Math.random() * ngos.length)].id : null,
            claimedAt: status !== 'pending' ? date : null,
            logDate: date,
            createdAt: date,
            updatedAt: date
          });
        }
      }
    }

    await WasteLog.bulkCreate(logs);
    console.log(`✅ Created ${kitchens.length} kitchens, ${ngos.length} NGOs, ${logs.length} waste logs`);

    // Create some claims for completed logs
    const claimedLogs = await WasteLog.findAll({ where: { status: ['claimed', 'completed'] } });
    const claimRecords = claimedLogs.map(log => ({
      wasteLogId: log.id,
      ngoId: log.claimedBy,
      kitchenId: log.kitchenId,
      status: log.status === 'completed' ? 'completed' : 'claimed',
      claimedAt: log.claimedAt,
      completedAt: log.status === 'completed' ? log.claimedAt : null
    }));

    await Claim.bulkCreate(claimRecords);
    console.log(`✅ Created ${claimRecords.length} claims`);

    console.log('\n🎉 Seed complete! Demo accounts:');
    console.log('Kitchen: kitchen1@demo.com / password123');
    console.log('NGO:     ngo1@demo.com / password123');

    process.exit(0);
  } catch (err) {
    console.error('Seed error:', err);
    process.exit(1);
  }
}

seed();
