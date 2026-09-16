// API Client — centralized fetch wrapper
const API_BASE = 'http://localhost:5000/api';

const api = {
  getToken() {
    return localStorage.getItem('token');
  },

  getUser() {
    const u = localStorage.getItem('user');
    return u ? JSON.parse(u) : null;
  },

  async request(method, endpoint, body = null) {
    const headers = { 'Content-Type': 'application/json' };
    const token = this.getToken();
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const opts = { method, headers };
    if (body) opts.body = JSON.stringify(body);

    const res = await fetch(`${API_BASE}${endpoint}`, opts);
    const data = await res.json();

    if (!res.ok) {
      throw new Error(data.error || 'Request failed');
    }
    return data;
  },

  get(endpoint) { return this.request('GET', endpoint); },
  post(endpoint, body) { return this.request('POST', endpoint, body); },
  patch(endpoint, body) { return this.request('PATCH', endpoint, body); },
  delete(endpoint) { return this.request('DELETE', endpoint); },
};
