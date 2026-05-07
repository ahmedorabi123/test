import { useEffect } from "react";
import { Routes, Route, Navigate } from "react-router-dom";
import { useDispatch, useSelector } from "react-redux";
import type { AppDispatch, RootState } from "./store";
import { bootstrapUser } from "./store/slices/authSlice";
import ProtectedRoute from "./components/ProtectedRoute";
import AppLayout from "./components/layout/AppLayout";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import ProductsPage from "./pages/ProductsPage";
import OrdersPage from "./pages/OrdersPage";
import InventoryPage from "./pages/InventoryPage";
import WarehousesPage from "./pages/WarehousesPage";
import AccountingPage from "./pages/AccountingPage";
import CustomersPage from "./pages/CustomersPage";
import NewCustomerPage from "./pages/NewCustomerPage";
import ShipmentsPage from "./pages/ShipmentsPage";
import ShipmentDetailPage from "./pages/ShipmentDetailPage";
import RefundsPage from "./pages/RefundsPage";
import RefundDetailPage from "./pages/RefundDetailPage";
import ManualOrderPage from "./pages/ManualOrderPage";
import PurchasesPage from "./pages/PurchasesPage";
import NewPurchaseOrderPage from "./pages/NewPurchaseOrderPage";
import PurchaseOrderDetailPage from "./pages/PurchaseOrderDetailPage";
import SuppliersPage from "./pages/SuppliersPage";
import NewSupplierPage from "./pages/NewSupplierPage";
import SupplierDetailPage from "./pages/SupplierDetailPage";
import AuditLogsPage from "./pages/AuditLogsPage";
import ProductionPage from "./pages/ProductionPage";
import BomEditorPage from "./pages/BomEditorPage";
import OrderDetailPage from "./pages/OrderDetailPage";
import CustomerDetailPage from "./pages/CustomerDetailPage";
import ProductDetailPage from "./pages/ProductDetailPage";
import NewProductPage from "./pages/NewProductPage";
import CollectionsPage from "./pages/CollectionsPage";
import CollectionDetailPage from "./pages/CollectionDetailPage";
import UsersPage from "./pages/UsersPage";

function App() {
  const dispatch = useDispatch<AppDispatch>();
  const token = useSelector((s: RootState) => s.auth.token);
  const user = useSelector((s: RootState) => s.auth.user);

  // Re-hydrate user profile after page refresh (token in localStorage but user not in state)
  useEffect(() => {
    if (token && !user) {
      dispatch(bootstrapUser());
    }
  }, [dispatch, token, user]);

  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route element={<ProtectedRoute />}>
        <Route element={<AppLayout />}>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/products" element={<ProductsPage />} />
          <Route path="/products/new" element={<NewProductPage />} />
          <Route path="/products/:id" element={<ProductDetailPage />} />
          <Route path="/collections" element={<CollectionsPage />} />
          <Route path="/collections/:id" element={<CollectionDetailPage />} />
          <Route path="/orders" element={<OrdersPage />} />
          <Route path="/orders/new" element={<ManualOrderPage />} />
          <Route path="/orders/:id" element={<OrderDetailPage />} />
          <Route path="/customers" element={<CustomersPage />} />
          <Route path="/customers/new" element={<NewCustomerPage />} />
          <Route path="/customers/:id" element={<CustomerDetailPage />} />
          <Route path="/shipments" element={<ShipmentsPage />} />
          <Route path="/shipments/:id" element={<ShipmentDetailPage />} />
          <Route path="/refunds" element={<RefundsPage />} />
          <Route path="/refunds/:id" element={<RefundDetailPage />} />
          <Route path="/purchases" element={<PurchasesPage />} />
          <Route path="/purchases/new" element={<NewPurchaseOrderPage />} />
          <Route path="/purchases/:id" element={<PurchaseOrderDetailPage />} />
          <Route path="/suppliers" element={<SuppliersPage />} />
          <Route path="/suppliers/new" element={<NewSupplierPage />} />
          <Route path="/suppliers/:id" element={<SupplierDetailPage />} />
          <Route path="/inventory" element={<InventoryPage />} />
          <Route path="/warehouses" element={<WarehousesPage />} />
          <Route path="/accounting" element={<AccountingPage />} />
          <Route path="/production" element={<ProductionPage />} />
          <Route path="/production/bom" element={<BomEditorPage />} />
          <Route path="/audit_logs" element={<AuditLogsPage />} />
          <Route path="/users" element={<UsersPage />} />
        </Route>
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default App;
