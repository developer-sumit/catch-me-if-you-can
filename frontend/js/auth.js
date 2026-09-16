// Auth utilities — login, register, logout, route protection

function showToast(message, isError = false) {
  let container = document.querySelector('.toast-container');
  if (!container) {
    container = document.createElement('div');
    container.className = 'toast-container';
    document.body.appendChild(container);
  }
  const toast = document.createElement('div');
  toast.className = `toast ${isError ? 'error' : ''}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => toast.remove(), 4000);
}

function requireAuth() {
  const token = localStorage.getItem('token');
  if (!token) {
    window.location.href = '/login.html';
    return false;
  }
  return true;
}

function requireRole(role) {
  const user = api.getUser();
  if (!user || user.role !== role) {
    window.location.href = user?.role === 'kitchen' ? '/kitchen/dashboard.html' : '/ngo/dashboard.html';
    return false;
  }
  return true;
}

function logout() {
  localStorage.removeItem('token');
  localStorage.removeItem('user');
  window.location.href = '/index.html';
}

function redirectIfLoggedIn() {
  const user = api.getUser();
  if (user) {
    window.location.href = user.role === 'kitchen' ? '/kitchen/dashboard.html' : '/ngo/dashboard.html';
  }
}

function getTheme() {
  const saved = localStorage.getItem('theme');
  if (saved) return saved;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  const toggleBtn = document.getElementById('themeToggleBtn');
  if (toggleBtn) {
    toggleBtn.innerHTML = theme === 'dark' ? '☀️' : '🌙';
  }
}

function toggleTheme() {
  const current = getTheme();
  const next = current === 'dark' ? 'light' : 'dark';
  localStorage.setItem('theme', next);
  applyTheme(next);
}

function updateNavbar() {
  const user = api.getUser();
  const navLinks = document.querySelector('.navbar-links');
  if (!navLinks) return;
  
  let html = '';
  if (user) {
    html += `
      <a href="/${user.role === 'kitchen' ? 'kitchen' : 'ngo'}/dashboard.html">📊 Dashboard</a>
      <span style="color: var(--text-secondary); font-size: 0.85rem;">👤 ${user.name}</span>
      <a href="#" onclick="logout()" class="btn btn-outline btn-sm">Logout</a>
    `;
  }
  html += `
    <button id="themeToggleBtn" onclick="toggleTheme()" class="btn btn-outline btn-sm" style="border-radius: 50%; padding: 0.5rem; width: 36px; height: 36px; display: flex; align-items: center; justify-content: center; margin-left: 0.5rem; border: none; font-size: 1.2rem;">
      ${getTheme() === 'dark' ? '☀️' : '🌙'}
    </button>
  `;
  navLinks.innerHTML = html;
  
  // Ensure the theme is correctly applied after rendering the button
  applyTheme(getTheme());
}

// Food type emoji mapping
const foodEmojis = {
  rice: '🍚', dal: '🍲', roti: '🫓', vegetables: '🥗', curry: '🍛',
  biryani: '🍚', bread: '🍞', fruits: '🍎', dairy: '🥛', other: '🍽️'
};

function getFoodEmoji(type) {
  return foodEmojis[type] || '🍽️';
}

function formatDate(dateStr) {
  return new Date(dateStr).toLocaleDateString('en-IN', {
    day: 'numeric', month: 'short', year: 'numeric'
  });
}

function timeAgo(dateStr) {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}
