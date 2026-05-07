import { createSlice, createAsyncThunk, PayloadAction } from "@reduxjs/toolkit";
import api from "../../api/client";

interface User {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  roles: string[];
  permissions?: string[];
}

interface AuthState {
  user: User | null;
  token: string | null;
  loading: boolean;
  error: string | null;
}

const TOKEN_KEY = "erp_token";

const initialState: AuthState = {
  user: null,
  token: localStorage.getItem(TOKEN_KEY),
  loading: false,
  error: null,
};

export const login = createAsyncThunk(
  "auth/login",
  async (
    credentials: { email: string; password: string },
    { rejectWithValue },
  ) => {
    try {
      const res = await api.post("/auth/login", { user: credentials });
      // Token comes from response body; header fallback for future middleware use
      const token =
        res.data.data?.token ||
        res.headers["authorization"]?.replace("Bearer ", "") ||
        "";
      return { token, user: res.data.data.user };
    } catch (err: unknown) {
      const error = err as {
        response?: { data?: { error?: { detail?: string } | string } };
      };
      const payload = error.response?.data?.error;
      const detail =
        (typeof payload === "object" ? payload.detail : payload) ??
        "Login failed";
      return rejectWithValue(
        typeof detail === "string" ? detail : "Login failed",
      );
    }
  },
);

export const logout = createAsyncThunk(
  "auth/logout",
  async (_, { getState }) => {
    const state = getState() as { auth: AuthState };
    await api.delete("/auth/logout", {
      headers: { Authorization: `Bearer ${state.auth.token}` },
    });
  },
);

export const bootstrapUser = createAsyncThunk(
  "auth/bootstrapUser",
  async (_, { rejectWithValue }) => {
    try {
      const res = await api.get("/auth/me");
      return res.data.data as User;
    } catch {
      return rejectWithValue("session_expired");
    }
  },
);

const authSlice = createSlice({
  name: "auth",
  initialState,
  reducers: {
    clearError(state) {
      state.error = null;
    },
  },
  extraReducers: (builder) => {
    builder
      .addCase(login.pending, (state) => {
        state.loading = true;
        state.error = null;
      })
      .addCase(
        login.fulfilled,
        (state, action: PayloadAction<{ token: string; user: User }>) => {
          state.loading = false;
          state.token = action.payload.token;
          state.user = action.payload.user;
          localStorage.setItem(TOKEN_KEY, action.payload.token);
          api.defaults.headers.common["Authorization"] =
            `Bearer ${action.payload.token}`;
        },
      )
      .addCase(login.rejected, (state, action) => {
        state.loading = false;
        state.error = action.payload as string;
      })
      .addCase(logout.fulfilled, (state) => {
        state.token = null;
        state.user = null;
        localStorage.removeItem(TOKEN_KEY);
        delete api.defaults.headers.common["Authorization"];
      })
      .addCase(bootstrapUser.fulfilled, (state, action) => {
        state.user = action.payload;
        state.loading = false;
      })
      .addCase(bootstrapUser.rejected, (state) => {
        // token is invalid / expired — clear everything so ProtectedRoute redirects to login
        state.token = null;
        state.user = null;
        localStorage.removeItem(TOKEN_KEY);
        delete api.defaults.headers.common["Authorization"];
      });
  },
});

export const { clearError } = authSlice.actions;
export default authSlice.reducer;
