import { Navigate, Outlet } from "react-router-dom";
import { useSelector } from "react-redux";
import type { RootState } from "../store";

export default function ProtectedRoute() {
  const token = useSelector((s: RootState) => s.auth.token);
  return token ? <Outlet /> : <Navigate to="/login" replace />;
}
