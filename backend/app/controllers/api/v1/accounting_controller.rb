module Api
  module V1
    class AccountingController < ApplicationController
      before_action :authorize_accounting

      # GET /api/v1/accounting/accounts?q=
      # Substring search across code and name; falls back to active list.
      def accounts
        scope = Account.active
        if params[:q].present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.downcase)}%"
          scope = scope.where("LOWER(code) LIKE :q OR LOWER(name) LIKE :q", q: term)
        end
        accounts = scope.order(:code).limit(100)
        render json: { data: accounts.map { |a| AccountSerializer.call(a) } }
      end

      # GET /api/v1/accounting/journal_entries?from=&to=&entry_type=&status=&q=&min_amount=&max_amount=&account_code=&page=&per_page=&sort=&dir=
      def journal_entries
        scope = JournalEntry.includes(journal_lines: :account)
        scope = scope.where("entry_date >= ?", params[:from]) if params[:from].present?
        scope = scope.where("entry_date <= ?", params[:to])   if params[:to].present?
        scope = scope.where(entry_type: params[:entry_type])  if params[:entry_type].present?
        scope = scope.where(status: params[:status])          if params[:status].present?
        scope = scope.search_text(params[:q])                 if params[:q].present?
        if params[:min_amount].present? || params[:max_amount].present?
          scope = scope.with_amount_between(
            params[:min_amount].present? ? params[:min_amount].to_d : nil,
            params[:max_amount].present? ? params[:max_amount].to_d : nil
          )
        end
        scope = scope.with_account_code(params[:account_code]) if params[:account_code].present?

        scope = apply_journal_sort(scope)

        page     = [params[:page].to_i, 1].max
        per_page = (params[:per_page].to_i.positive? ? params[:per_page].to_i : 25).clamp(1, 200)
        total    = scope.count
        records  = scope.offset((page - 1) * per_page).limit(per_page)

        render json: {
          data: records.map { |e| JournalEntrySerializer.call(e, include_lines: false) },
          meta: { page: page, per_page: per_page, total: total }
        }
      end

      # GET /api/v1/accounting/journal_entries/:id
      def journal_entry
        entry = JournalEntry.includes(journal_lines: :account).find(params[:id])
        render json: { data: JournalEntrySerializer.call(entry, include_lines: true) }
      end

      # GET /api/v1/accounting/accounts/:code/ledger?from=&to=&q=&page=&per_page=
      # Returns posted journal lines for a single account with a running balance.
      def account_ledger
        account = Account.find_by!(code: params[:code])

        lines = account.journal_lines
                       .joins(:journal_entry)
                       .where("journal_entries.status = 'posted'")
        lines = lines.where("journal_entries.entry_date >= ?", params[:from]) if params[:from].present?
        lines = lines.where("journal_entries.entry_date <= ?", params[:to])   if params[:to].present?
        if params[:q].present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s)}%"
          lines = lines.where(
            "journal_lines.description ILIKE :q OR journal_entries.description ILIKE :q",
            q: term
          )
        end

        # Compute running balance in SQL using a window function. Postgres-only.
        sign_expr =
          if account.normal_side == "debit"
            "CASE WHEN journal_lines.side = 'debit' THEN journal_lines.amount ELSE -journal_lines.amount END"
          else
            "CASE WHEN journal_lines.side = 'credit' THEN journal_lines.amount ELSE -journal_lines.amount END"
          end

        ordered = lines.select(
          "journal_lines.id AS line_id",
          "journal_lines.amount",
          "journal_lines.side",
          "journal_lines.description AS line_description",
          "journal_entries.id AS entry_id",
          "journal_entries.entry_date",
          "journal_entries.description AS entry_description",
          "journal_entries.entry_type",
          "SUM(#{sign_expr}) OVER (ORDER BY journal_entries.entry_date, journal_lines.created_at, journal_lines.id) AS running_balance"
        ).order("journal_entries.entry_date ASC, journal_lines.created_at ASC, journal_lines.id ASC")

        page     = [params[:page].to_i, 1].max
        per_page = (params[:per_page].to_i.positive? ? params[:per_page].to_i : 50).clamp(1, 200)
        total    = lines.count
        rows     = ordered.offset((page - 1) * per_page).limit(per_page)

        data = rows.map do |r|
          {
            line_id:           r["line_id"],
            entry_id:          r["entry_id"],
            entry_date:        r["entry_date"],
            entry_description: r["entry_description"],
            entry_type:        r["entry_type"],
            side:              r["side"],
            amount:            r["amount"].to_f,
            description:       r["line_description"],
            running_balance:   r["running_balance"].to_f
          }
        end

        render json: {
          data: data,
          meta: {
            page: page, per_page: per_page, total: total,
            account: AccountSerializer.call(account)
          }
        }
      end

      # GET /api/v1/accounting/trial_balance?as_of=
      def trial_balance
        as_of = params[:as_of].present? ? Date.parse(params[:as_of]) : Date.current

        rows = Account.active.order(:code).map do |account|
          debits  = account.journal_lines
                           .joins(:journal_entry)
                           .where(side: "debit")
                           .where("journal_entries.entry_date <= ?", as_of)
                           .where("journal_entries.status = 'posted'")
                           .sum(:amount)
          credits = account.journal_lines
                           .joins(:journal_entry)
                           .where(side: "credit")
                           .where("journal_entries.entry_date <= ?", as_of)
                           .where("journal_entries.status = 'posted'")
                           .sum(:amount)
          balance = account.normal_side == "debit" ? debits - credits : credits - debits

          { code: account.code, name: account.name, account_type: account.account_type,
            normal_side: account.normal_side, debits: debits.to_f, credits: credits.to_f,
            balance: balance.to_f }
        end.reject { |r| r[:debits].zero? && r[:credits].zero? }

        total_debits  = rows.sum { |r| r[:debits] }
        total_credits = rows.sum { |r| r[:credits] }

        render json: {
          data:     rows,
          as_of:    as_of,
          balanced: (total_debits - total_credits).abs < 0.01,
          totals:   { debits: total_debits.to_f, credits: total_credits.to_f }
        }
      end

      # GET /api/v1/accounting/pnl?from=&to=
      def pnl
        from = params[:from].present? ? Date.parse(params[:from]) : Date.current.beginning_of_month
        to   = params[:to].present?   ? Date.parse(params[:to])   : Date.current

        revenue_accounts = Account.revenue.active
        expense_accounts = Account.expenses.active

        revenue = revenue_accounts.map do |a|
          credits = a.journal_lines.joins(:journal_entry)
                     .where("journal_entries.entry_date" => from..to)
                     .where("journal_entries.status" => "posted")
                     .where(side: "credit").sum(:amount)
          debits  = a.journal_lines.joins(:journal_entry)
                     .where("journal_entries.entry_date" => from..to)
                     .where("journal_entries.status" => "posted")
                     .where(side: "debit").sum(:amount)
          { code: a.code, name: a.name, amount: (credits - debits).to_f }
        end.reject { |r| r[:amount].zero? }

        expenses = expense_accounts.map do |a|
          debits  = a.journal_lines.joins(:journal_entry)
                     .where("journal_entries.entry_date" => from..to)
                     .where("journal_entries.status" => "posted")
                     .where(side: "debit").sum(:amount)
          credits = a.journal_lines.joins(:journal_entry)
                     .where("journal_entries.entry_date" => from..to)
                     .where("journal_entries.status" => "posted")
                     .where(side: "credit").sum(:amount)
          { code: a.code, name: a.name, amount: (debits - credits).to_f }
        end.reject { |r| r[:amount].zero? }

        total_revenue  = revenue.sum { |r| r[:amount] }
        total_expenses = expenses.sum { |r| r[:amount] }

        render json: {
          from:           from,
          to:             to,
          revenue:        revenue,
          expenses:       expenses,
          total_revenue:  total_revenue.to_f,
          total_expenses: total_expenses.to_f,
          net_income:     (total_revenue - total_expenses).to_f
        }
      end

      # POST /api/v1/accounting/post_order/:order_id
      def post_order
        order = Order.find(params[:order_id])
        entry = Accounting::PostSaleJournalHandler.call(order)
        if entry
          render json: { data: JournalEntrySerializer.call(entry.reload, include_lines: true) }, status: :created
        else
          render json: { message: "Already posted or order not paid" }, status: :ok
        end
      end

      # POST /api/v1/accounting/journal_entries
      # Body: { entry_date:, description:, currency?: "EGP", entry_type?: "manual",
      #         lines: [{ account_code:, side: "debit"|"credit", amount:, description?, supplier_id? }, ...] }
      def create_journal_entry
        lines_attrs = Array(params[:lines]).map do |l|
          {
            account_code: l[:account_code],
            side:         l[:side],
            amount:       l[:amount].to_s.to_d,
            description:  l[:description],
            supplier_id:  l[:supplier_id]
          }
        end

        return render json: { error: { type: "invalid", detail: "lines required" } }, status: :unprocessable_entity if lines_attrs.empty?

        debits  = lines_attrs.select { |l| l[:side] == "debit" }.sum  { |l| l[:amount].to_d }
        credits = lines_attrs.select { |l| l[:side] == "credit" }.sum { |l| l[:amount].to_d }
        if (debits - credits).abs > 0.001
          return render json: { error: { type: "invalid", detail: "Lines unbalanced: debits=#{debits} credits=#{credits}" } }, status: :unprocessable_entity
        end

        entry = JournalEntry.post!(
          {
            entry_date:  params[:entry_date].present? ? Date.parse(params[:entry_date].to_s) : Date.current,
            description: params[:description].presence || "Manual journal entry",
            currency:    (params[:currency].presence || "EGP").upcase,
            entry_type:  (params[:entry_type].presence || "manual"),
            source_type: params[:source_type],
            source_id:   params[:source_id]
          },
          lines_attrs
        )
        AuditLog.record(user: current_user, action: "accounting.journal.post",
                        subject: entry, request: request)
        render json: { data: JournalEntrySerializer.call(entry.reload, include_lines: true) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: { type: "invalid", detail: e.message } }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound => e
        render json: { error: { type: "invalid", detail: e.message } }, status: :unprocessable_entity
      end

      # GET /api/v1/accounting/balance_sheet?as_of=
      def balance_sheet
        as_of = params[:as_of].present? ? Date.parse(params[:as_of]) : Date.current

        rows_for = ->(scope) do
          scope.active.order(:code).map do |a|
            debits = a.journal_lines.joins(:journal_entry)
                     .where("journal_entries.entry_date <= ?", as_of)
                     .where("journal_entries.status = 'posted'")
                     .where(side: "debit").sum(:amount)
            credits = a.journal_lines.joins(:journal_entry)
                     .where("journal_entries.entry_date <= ?", as_of)
                     .where("journal_entries.status = 'posted'")
                     .where(side: "credit").sum(:amount)
            balance = a.normal_side == "debit" ? debits - credits : credits - debits
            { code: a.code, name: a.name, balance: balance.to_f }
          end.reject { |r| r[:balance].zero? }
        end

        assets      = rows_for.call(Account.assets)
        liabilities = rows_for.call(Account.liabilities)
        equity      = rows_for.call(Account.equity)

        # Retained earnings = cumulative net income (revenue - expense) up to as_of
        revenue_total = Account.revenue.active.joins(:journal_lines => :journal_entry)
                               .where("journal_entries.entry_date <= ?", as_of)
                               .where("journal_entries.status = 'posted'")
                               .where("journal_lines.side = 'credit'").sum("journal_lines.amount") -
                        Account.revenue.active.joins(:journal_lines => :journal_entry)
                               .where("journal_entries.entry_date <= ?", as_of)
                               .where("journal_entries.status = 'posted'")
                               .where("journal_lines.side = 'debit'").sum("journal_lines.amount")
        expense_total = Account.expenses.active.joins(:journal_lines => :journal_entry)
                               .where("journal_entries.entry_date <= ?", as_of)
                               .where("journal_entries.status = 'posted'")
                               .where("journal_lines.side = 'debit'").sum("journal_lines.amount") -
                        Account.expenses.active.joins(:journal_lines => :journal_entry)
                               .where("journal_entries.entry_date <= ?", as_of)
                               .where("journal_entries.status = 'posted'")
                               .where("journal_lines.side = 'credit'").sum("journal_lines.amount")
        retained = (revenue_total - expense_total).to_f

        total_assets      = assets.sum { |r| r[:balance] }
        total_liabilities = liabilities.sum { |r| r[:balance] }
        total_equity      = equity.sum { |r| r[:balance] } + retained

        render json: {
          as_of: as_of,
          assets:             { rows: assets, total: total_assets.to_f },
          liabilities:        { rows: liabilities, total: total_liabilities.to_f },
          equity:             { rows: equity, retained_earnings: retained, total: total_equity.to_f },
          balanced:           (total_assets - (total_liabilities + total_equity)).abs < 0.01,
          total_liab_equity:  (total_liabilities + total_equity).to_f
        }
      end

      private

      JOURNAL_SORT_KEYS = %w[entry_date description status entry_type created_at].freeze

      def apply_journal_sort(scope)
        key = params[:sort].to_s
        dir = params[:dir].to_s.downcase == "asc" ? :asc : :desc
        if JOURNAL_SORT_KEYS.include?(key)
          scope.order(key => dir, created_at: :desc)
        else
          scope.order(entry_date: :desc, created_at: :desc)
        end
      end

      def authorize_accounting
        # Use a synthetic record class for policy lookup
        policy = AccountingPolicy.new(current_user, Account)
        raise Pundit::NotAuthorizedError unless policy.index?
      end
    end
  end
end
