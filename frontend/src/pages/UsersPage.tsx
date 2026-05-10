import { useEffect, useMemo, useState } from "react";
import {
  usersApi,
  rolesApi,
  permissionsApi,
  type User,
  type Role,
  type PermissionDef,
} from "../api/users";

type Tab = "users" | "roles";

export default function UsersPage() {
  const [tab, setTab] = useState<Tab>("users");
  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Users & Roles</h1>
        <p className="text-slate-500 text-sm mt-1">
          Manage who can access the ERP and what they can do.
        </p>
      </div>
      <div className="flex gap-1 border-b border-slate-200">
        {(["users", "roles"] as Tab[]).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
              tab === t
                ? "border-indigo-600 text-indigo-700"
                : "border-transparent text-slate-500 hover:text-slate-700 hover:border-slate-300"
            }`}
          >
            {t === "users" ? "Users" : "Roles"}
          </button>
        ))}
      </div>
      {tab === "users" ? <UsersTab /> : <RolesTab />}
    </div>
  );
}

function UsersTab() {
  const [users, setUsers] = useState<User[]>([]);
  const [roles, setRoles] = useState<Role[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({
    email: "",
    first_name: "",
    last_name: "",
    password: "",
  });

  const reload = async () => {
    setLoading(true);
    setError("");
    try {
      const [u, r] = await Promise.all([usersApi.list(), rolesApi.list()]);
      setUsers(u.data);
      setRoles(r.data);
    } catch (e) {
      setError(getMessage(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    reload();
  }, []);

  const submitCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    try {
      await usersApi.create({
        email: form.email,
        first_name: form.first_name,
        last_name: form.last_name,
        password: form.password || undefined,
      });
      setCreating(false);
      setForm({ email: "", first_name: "", last_name: "", password: "" });
      reload();
    } catch (e) {
      setError(getMessage(e));
    }
  };

  const assignRole = async (userId: string, roleId: string) => {
    if (!roleId) return;
    try {
      await usersApi.assignRole(userId, roleId);
      reload();
    } catch (e) {
      setError(getMessage(e));
    }
  };

  const removeRole = async (userId: string, roleId: string) => {
    try {
      await usersApi.removeRole(userId, roleId);
      reload();
    } catch (e) {
      setError(getMessage(e));
    }
  };

  const toggleActive = async (u: User) => {
    try {
      await usersApi.update(u.id, { active: !u.active });
      reload();
    } catch (e) {
      setError(getMessage(e));
    }
  };

  if (loading) return <div className="text-slate-500 text-sm">Loading…</div>;

  return (
    <div className="space-y-4">
      {error && (
        <div className="bg-red-50 text-red-700 p-2 rounded text-sm">
          {error}
        </div>
      )}

      <div className="flex justify-end">
        <button
          onClick={() => setCreating((c) => !c)}
          className="bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-medium px-3 py-1.5 rounded"
        >
          {creating ? "Cancel" : "+ New user"}
        </button>
      </div>

      {creating && (
        <form
          onSubmit={submitCreate}
          className="bg-white rounded shadow p-4 grid grid-cols-2 gap-3"
        >
          <label className="text-sm">
            <span className="block text-slate-600 mb-1">Email *</span>
            <input
              type="email"
              required
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              className="w-full border border-slate-300 rounded px-3 py-2"
            />
          </label>
          <label className="text-sm">
            <span className="block text-slate-600 mb-1">
              Password (auto-generated if blank)
            </span>
            <input
              type="text"
              value={form.password}
              onChange={(e) => setForm({ ...form, password: e.target.value })}
              className="w-full border border-slate-300 rounded px-3 py-2"
            />
          </label>
          <label className="text-sm">
            <span className="block text-slate-600 mb-1">First name *</span>
            <input
              required
              value={form.first_name}
              onChange={(e) => setForm({ ...form, first_name: e.target.value })}
              className="w-full border border-slate-300 rounded px-3 py-2"
            />
          </label>
          <label className="text-sm">
            <span className="block text-slate-600 mb-1">Last name *</span>
            <input
              required
              value={form.last_name}
              onChange={(e) => setForm({ ...form, last_name: e.target.value })}
              className="w-full border border-slate-300 rounded px-3 py-2"
            />
          </label>
          <div className="col-span-2 flex justify-end">
            <button
              type="submit"
              className="bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-medium px-4 py-2 rounded"
            >
              Create user
            </button>
          </div>
        </form>
      )}

      <div className="bg-white rounded shadow overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-slate-50 text-slate-600 text-xs uppercase">
            <tr>
              <th className="text-left px-3 py-2">Name</th>
              <th className="text-left px-3 py-2">Email</th>
              <th className="text-left px-3 py-2">Roles</th>
              <th className="text-left px-3 py-2">Last login</th>
              <th className="text-left px-3 py-2">Status</th>
              <th className="px-3 py-2"></th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id} className="border-t border-slate-100">
                <td className="px-3 py-2 font-medium text-slate-800">
                  {u.first_name} {u.last_name}
                </td>
                <td className="px-3 py-2 text-slate-600">{u.email}</td>
                <td className="px-3 py-2">
                  <div className="flex flex-wrap items-center gap-1">
                    {u.roles.map((r) => (
                      <span
                        key={r.id}
                        className="inline-flex items-center gap-1 bg-indigo-50 text-indigo-700 text-xs px-2 py-0.5 rounded"
                      >
                        {r.name}
                        <button
                          onClick={() => removeRole(u.id, r.id)}
                          className="text-indigo-500 hover:text-red-600"
                          title="Remove role"
                        >
                          ×
                        </button>
                      </span>
                    ))}
                    <select
                      value=""
                      onChange={(e) => assignRole(u.id, e.target.value)}
                      className="border border-slate-200 text-xs rounded px-1 py-0.5"
                    >
                      <option value="">+ Add role…</option>
                      {roles
                        .filter((r) => !u.roles.find((ur) => ur.id === r.id))
                        .map((r) => (
                          <option key={r.id} value={r.id}>
                            {r.name}
                          </option>
                        ))}
                    </select>
                  </div>
                </td>
                <td className="px-3 py-2 text-slate-500 text-xs">
                  {u.last_login_at
                    ? new Date(u.last_login_at).toLocaleString()
                    : "—"}
                </td>
                <td className="px-3 py-2">
                  <span
                    className={`text-xs px-2 py-0.5 rounded ${
                      u.active
                        ? "bg-emerald-50 text-emerald-700"
                        : "bg-slate-100 text-slate-500"
                    }`}
                  >
                    {u.active ? "Active" : "Inactive"}
                  </span>
                </td>
                <td className="px-3 py-2 text-right">
                  <button
                    onClick={() => toggleActive(u)}
                    className="text-indigo-600 hover:text-indigo-800 text-xs"
                  >
                    {u.active ? "Deactivate" : "Reactivate"}
                  </button>
                </td>
              </tr>
            ))}
            {users.length === 0 && (
              <tr>
                <td
                  colSpan={6}
                  className="text-center py-6 text-slate-400 text-sm"
                >
                  No users yet
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function RolesTab() {
  const [roles, setRoles] = useState<Role[]>([]);
  const [permissions, setPermissions] = useState<PermissionDef[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [editing, setEditing] = useState<Role | null>(null);
  const [creating, setCreating] = useState(false);

  const reload = async () => {
    setLoading(true);
    setError("");
    try {
      const [r, p] = await Promise.all([rolesApi.list(), permissionsApi.list()]);
      setRoles(r.data);
      setPermissions(p.data);
    } catch (e) {
      setError(getMessage(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    reload();
  }, []);

  const onDestroy = async (role: Role) => {
    if (!window.confirm(`Delete role "${role.name}"?`)) return;
    try {
      await rolesApi.destroy(role.id);
      reload();
    } catch (e) {
      setError(getMessage(e));
    }
  };

  if (loading) return <div className="text-slate-500 text-sm">Loading…</div>;

  return (
    <div className="space-y-4">
      {error && (
        <div className="bg-red-50 text-red-700 p-2 rounded text-sm">
          {error}
        </div>
      )}

      <div className="flex justify-end">
        <button
          onClick={() => setCreating(true)}
          className="bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-medium px-3 py-1.5 rounded"
        >
          + New role
        </button>
      </div>

      <div className="grid md:grid-cols-2 gap-4">
        {roles.map((r) => (
          <div key={r.id} className="bg-white rounded shadow p-4">
            <div className="flex items-baseline justify-between gap-2">
              <h3 className="text-lg font-semibold text-slate-800">
                {r.name}
                {r.system && (
                  <span className="ml-2 text-[10px] uppercase tracking-wide text-slate-400">
                    System
                  </span>
                )}
              </h3>
              <span className="text-xs text-slate-400">
                {r.permissions.length} permissions
              </span>
            </div>
            {r.description && (
              <p className="text-sm text-slate-500 mt-1">{r.description}</p>
            )}
            <div className="mt-3 flex flex-wrap gap-1">
              {r.permissions.map((p) => (
                <span
                  key={p}
                  className="text-xs bg-slate-100 text-slate-700 px-2 py-0.5 rounded"
                >
                  {p}
                </span>
              ))}
              {r.permissions.length === 0 && (
                <span className="text-xs text-slate-400">No permissions</span>
              )}
            </div>
            <div className="mt-3 flex justify-end gap-2 text-xs">
              <button
                onClick={() => setEditing(r)}
                className="text-indigo-600 hover:text-indigo-800"
              >
                Edit
              </button>
              {!r.system && (
                <button
                  onClick={() => onDestroy(r)}
                  className="text-red-600 hover:text-red-800"
                >
                  Delete
                </button>
              )}
            </div>
          </div>
        ))}
      </div>

      {(creating || editing) && (
        <RoleEditor
          role={editing}
          permissions={permissions}
          onClose={() => {
            setCreating(false);
            setEditing(null);
          }}
          onSaved={() => {
            setCreating(false);
            setEditing(null);
            reload();
          }}
        />
      )}
    </div>
  );
}

function RoleEditor({
  role,
  permissions,
  onClose,
  onSaved,
}: {
  role: Role | null;
  permissions: PermissionDef[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const isEdit = !!role;
  const isSystem = !!role?.system;
  const [name, setName] = useState(role?.name ?? "");
  const [description, setDescription] = useState(role?.description ?? "");
  const [selected, setSelected] = useState<Set<string>>(
    new Set(role?.permissions ?? []),
  );
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);

  const grouped = useMemo(() => {
    const groups: Record<string, PermissionDef[]> = {};
    for (const p of permissions) {
      (groups[p.resource] ||= []).push(p);
    }
    return groups;
  }, [permissions]);

  const togglePerm = (key: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  const toggleResource = (resource: string) => {
    const keys = (grouped[resource] || []).map((p) => p.key);
    const allOn = keys.every((k) => selected.has(k));
    setSelected((prev) => {
      const next = new Set(prev);
      keys.forEach((k) => (allOn ? next.delete(k) : next.add(k)));
      return next;
    });
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setSaving(true);
    try {
      const payload = {
        name: name.trim(),
        description: description.trim(),
        permissions: Array.from(selected),
      };
      if (isEdit && role) {
        await rolesApi.update(role.id, payload);
      } else {
        await rolesApi.create(payload);
      }
      onSaved();
    } catch (e) {
      setError(getMessage(e));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/30 flex items-center justify-center p-4">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-3xl p-5 max-h-[90vh] overflow-y-auto">
        <div className="flex items-baseline justify-between mb-3">
          <h3 className="text-lg font-semibold">
            {isEdit ? `Edit role: ${role?.name}` : "New role"}
          </h3>
          {isSystem && (
            <span className="text-xs text-amber-700 bg-amber-50 rounded px-2 py-0.5">
              System role — name is locked
            </span>
          )}
        </div>
        <form onSubmit={submit} className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <label className="text-sm">
              <span className="block text-slate-600 mb-1">Name *</span>
              <input
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
                disabled={isSystem}
                className="w-full border border-slate-300 rounded px-3 py-2 disabled:bg-slate-100"
              />
            </label>
            <label className="text-sm">
              <span className="block text-slate-600 mb-1">Description</span>
              <input
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                className="w-full border border-slate-300 rounded px-3 py-2"
              />
            </label>
          </div>

          <div>
            <div className="text-sm font-medium text-slate-700 mb-2">
              Permissions ({selected.size})
            </div>
            <div className="space-y-3">
              {Object.entries(grouped).map(([resource, perms]) => {
                const keys = perms.map((p) => p.key);
                const allOn = keys.every((k) => selected.has(k));
                const anyOn = keys.some((k) => selected.has(k));
                return (
                  <div
                    key={resource}
                    className="border border-slate-200 rounded"
                  >
                    <div className="flex items-center justify-between bg-slate-50 px-3 py-2">
                      <span className="text-sm font-medium capitalize">
                        {resource.replace(/_/g, " ")}
                      </span>
                      <button
                        type="button"
                        onClick={() => toggleResource(resource)}
                        className="text-xs text-indigo-600 hover:text-indigo-800"
                      >
                        {allOn
                          ? "Clear all"
                          : anyOn
                            ? "Select all"
                            : "Select all"}
                      </button>
                    </div>
                    <div className="p-3 grid grid-cols-2 sm:grid-cols-3 gap-1">
                      {perms.map((p) => (
                        <label
                          key={p.key}
                          className="flex items-center gap-2 text-sm text-slate-700"
                        >
                          <input
                            type="checkbox"
                            checked={selected.has(p.key)}
                            onChange={() => togglePerm(p.key)}
                          />
                          <span className="font-mono text-xs">{p.action}</span>
                        </label>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {error && (
            <div className="bg-red-50 text-red-700 text-sm p-2 rounded">
              {error}
            </div>
          )}

          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              className="text-sm px-3 py-1.5 rounded border border-slate-300"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={saving}
              className="text-sm bg-emerald-600 hover:bg-emerald-700 disabled:bg-slate-400 text-white font-medium px-4 py-1.5 rounded"
            >
              {saving ? "Saving…" : isEdit ? "Save changes" : "Create role"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function getMessage(e: unknown): string {
  const err = e as {
    response?: { data?: { error?: string; message?: string } };
    message?: string;
  };
  return (
    err?.response?.data?.error ||
    err?.response?.data?.message ||
    err?.message ||
    "Something went wrong"
  );
}
