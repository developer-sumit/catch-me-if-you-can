const { DataTypes } = require('sequelize');
const sequelize = require('../config/db');
const User = require('./User');
const WasteLog = require('./WasteLog');

const Claim = sequelize.define('Claim', {
  id: {
    type: DataTypes.INTEGER,
    primaryKey: true,
    autoIncrement: true
  },
  wasteLogId: {
    type: DataTypes.INTEGER,
    allowNull: false,
    field: 'waste_log_id',
    references: { model: WasteLog, key: 'id' }
  },
  ngoId: {
    type: DataTypes.INTEGER,
    allowNull: false,
    field: 'ngo_id',
    references: { model: User, key: 'id' }
  },
  kitchenId: {
    type: DataTypes.INTEGER,
    allowNull: false,
    field: 'kitchen_id',
    references: { model: User, key: 'id' }
  },
  status: {
    type: DataTypes.ENUM('claimed', 'picked_up', 'completed', 'cancelled'),
    defaultValue: 'claimed'
  },
  claimedAt: {
    type: DataTypes.DATE,
    defaultValue: DataTypes.NOW,
    field: 'claimed_at'
  },
  completedAt: {
    type: DataTypes.DATE,
    allowNull: true,
    field: 'completed_at'
  }
}, {
  tableName: 'claims',
  underscored: true
});

// Associations
Claim.belongsTo(WasteLog, { as: 'wasteLog', foreignKey: 'waste_log_id' });
Claim.belongsTo(User, { as: 'ngo', foreignKey: 'ngo_id' });
Claim.belongsTo(User, { as: 'kitchen', foreignKey: 'kitchen_id' });
WasteLog.hasMany(Claim, { as: 'claims', foreignKey: 'waste_log_id' });
User.hasMany(Claim, { as: 'ngoClaims', foreignKey: 'ngo_id' });

module.exports = Claim;
