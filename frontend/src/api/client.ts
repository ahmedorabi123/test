import axios from "axios";

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL + "/api/v1",
  headers: { "Content-Type": "application/json" },
});

// Attach stored token on startup
const stored = localStorage.getItem("erp_token");
if (stored) {
  api.defaults.headers.common["Authorization"] = `Bearer ${stored}`;
}

// Redirect to login on 401, but not when the login endpoint itself returns 401
// (that means wrong credentials — let the caller handle the error).
api.interceptors.response.use(
  (res) => res,
  (err) => {
    const isLoginRequest = err.config?.url?.includes("/auth/login");
    if (err.response?.status === 401 && !isLoginRequest) {
      localStorage.removeItem("erp_token");
      window.location.href = "/login";
    }
    return Promise.reject(err);
  },
);

export default api;
