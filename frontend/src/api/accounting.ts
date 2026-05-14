import api from "./client";
import type { AxiosResponse } from "axios";

export interface Account {
  id: string;
  code: string;
  name: string;
  account_type: "asset" | "liability" | "equity" | "revenue" | "expense";
  normal_side: "debit" | "credit";
  currency: string;
  active: boolean;
  description?: string;
}

export interface JournalLine {
  id: string;
  account_code: string;
  account_name: string;
  side: "debit" | "credit";
  amount: number;
  currency: string;
  description?: string;
  supplier_id?: string | null;
  supplier_code?: string | null;
  supplier_name?: string | null;
}

export interface JournalEntry {
  id: string;
  entry_date: string;
  description: string;
  status: "draft" | "posted" | "reversed";
  currency: string;
  entry_type?: string;
  source_type?: string;
  source_id?: string;
  total_debits: number;
  total_credits: number;
  created_at: string;
  lines?: JournalLine[];
}

export interface JournalEntriesMeta {
  page: number;
  per_page: number;
  total: number;
}

export interface TrialBalanceRow {
  code: string;
  name: string;
  account_type: string;
  normal_side: string;
  debits: number;
  credits: number;
  balance: number;
}

export interface TrialBalance {
  data: TrialBalanceRow[];
  as_of: string;
  balanced: boolean;
  totals: { debits: number; credits: number };
}

export interface PnlRow {
  code: string;
  name: string;
  amount: number;
}

export interface Pnl {
  from: string;
  to: string;
  revenue: PnlRow[];
  expenses: PnlRow[];
  total_revenue: number;
  total_expenses: number;
  net_income: number;
}

export interface BalanceSheetRow {
  code: string;
  name: string;
  balance: number;
}

export interface BalanceSheet {
  as_of: string;
  assets: { rows: BalanceSheetRow[]; total: number };
  liabilities: { rows: BalanceSheetRow[]; total: number };
  equity: { rows: BalanceSheetRow[]; retained_earnings: number; total: number };
  balanced: boolean;
  total_liab_equity: number;
}

const BASE = "/accounting";

export const accountingApi = {
  accounts: (params?: { q?: string }): Promise<{ data: Account[] }> =>
    api
      .get<{ data: Account[] }>(`${BASE}/accounts`, { params })
      .then((r: AxiosResponse<{ data: Account[] }>) => r.data),

  journalEntries: (params?: {
    from?: string;
    to?: string;
    entry_type?: string;
    status?: string;
    page?: number;
    per_page?: number;
    sort?: string;
    dir?: "asc" | "desc";
  }): Promise<{ data: JournalEntry[]; meta: JournalEntriesMeta }> =>
    api
      .get<{
        data: JournalEntry[];
        meta: JournalEntriesMeta;
      }>(`${BASE}/journal_entries`, { params })
      .then(
        (
          r: AxiosResponse<{ data: JournalEntry[]; meta: JournalEntriesMeta }>,
        ) => r.data,
      ),

  journalEntry: (id: string): Promise<{ data: JournalEntry }> =>
    api
      .get<{ data: JournalEntry }>(`${BASE}/journal_entries/${id}`)
      .then((r: AxiosResponse<{ data: JournalEntry }>) => r.data),

  trialBalance: (asOf?: string): Promise<TrialBalance> =>
    api
      .get<TrialBalance>(`${BASE}/trial_balance`, {
        params: asOf ? { as_of: asOf } : {},
      })
      .then((r: AxiosResponse<TrialBalance>) => r.data),

  pnl: (from?: string, to?: string): Promise<Pnl> =>
    api
      .get<Pnl>(`${BASE}/pnl`, { params: { from, to } })
      .then((r: AxiosResponse<Pnl>) => r.data),

  balanceSheet: (asOf?: string): Promise<BalanceSheet> =>
    api
      .get<BalanceSheet>(`${BASE}/balance_sheet`, {
        params: asOf ? { as_of: asOf } : {},
      })
      .then((r: AxiosResponse<BalanceSheet>) => r.data),

  postOrder: (orderId: string): Promise<{ data: JournalEntry }> =>
    api
      .post<{ data: JournalEntry }>(`${BASE}/post_order/${orderId}`)
      .then((r: AxiosResponse<{ data: JournalEntry }>) => r.data),

  createJournalEntry: (payload: {
    entry_date: string;
    description: string;
    currency?: string;
    entry_type?: string;
    source_type?: string;
    source_id?: string;
    lines: Array<{
      account_code: string;
      side: "debit" | "credit";
      amount: string;
      description?: string;
      supplier_id?: string;
    }>;
  }): Promise<{ data: JournalEntry }> =>
    api
      .post<{ data: JournalEntry }>(`${BASE}/journal_entries`, payload)
      .then((r: AxiosResponse<{ data: JournalEntry }>) => r.data),
};
