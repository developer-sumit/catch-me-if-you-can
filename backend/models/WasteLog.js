const { DataTypes } = require('sequelize');
const sequelize = require('../config/db');
const User = require('./User');

const WasteLog = sequelize.define('WasteLog', {
  id: {
    type: DataTypes.INTEGER,
    primaryKey: true,
    autoIncrement: true
  },
  kitchenId: {
    type: DataTypes.INTEGER,
    allowNull: false,
    field: 'kitchen_id',
    references: { model: User, key: 'id' }
  },
  foodType: {
    type: DataTypes.ENUM('rice', 'dal', 'roti', 'vegetables', 'curry', 'biryani', 'bread', 'fruits', 'dairy', 'other'),
    allowNull: false,
    field: 'food_type'
  },
  quantity: {
    type: DataTypes.FLOAT,
    allowNull: false
  },
  unit: {
    type: DataTypes.STRING,
    defaultValue: 'kg'
  },
  status: {
    type: DataTypes.ENUM('pending', 'claimed', 'completed', 'expired'),
    defaultValue: 'pending'
  },
  claimedBy: {
    type: DataTypes.INTEGER,
    allowNull: true,
    field: 'claimed_by',
    references: { model: User, key: 'id' }
  },
  claimedAt: {
    type: DataTypes.DATE,
    allowNull: true,
    field: 'claimed_at'
  },
  notes: {
    type: DataTypes.TEXT,
    allowNull: true
  },
  logDate: {
    type: DataTypes.DATEONLY,
    defaultValue: DataTypes.NOW,
    field: 'log_date'
  }
}, {
  tableName: 'waste_logs',
  underscored: true
});

// Associations
WasteLog.belongsTo(User, { as: 'kitchen', foreignKey: 'kitchen_id' });
WasteLog.belongsTo(User, { as: 'claimer', foreignKey: 'claimed_by' });
User.hasMany(WasteLog, { as: 'wasteLogs', foreignKey: 'kitchen_id' });

module.exports = WasteLog;
