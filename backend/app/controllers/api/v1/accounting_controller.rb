module Api
  module V1
    class AccountingController < ApplicationController
      before_action :authorize_accounting

      # GET /api/v1/accounting/accounts
      def accounts
        accounts = Account.active.order(:code)
        render json: { data: accounts.map { |a| AccountSerializer.call(a) } }
      end

      # GET /api/v1/accounting/journal_entries?from=&to=&entry_type=&page=&per_page=&sort=&dir=
      def journal_entries
        scope = JournalEntry.includes(journal_lines: :account)
        scope = scope.where("entry_date >= ?", params[:from]) if params[:from].present?
        scope = scope.where("entry_date <= ?", params[:to])   if params[:to].present?
        scope = scope.where(entry_type: params[:entry_type])  if params[:entry_type].present?
        scope = scope.where(status: params[:status])          if params[:status].present?

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

      # POST /api/v1/accounting/payroll_entries
      # Body: { period: "2025-04", total_amount: "12000.00", currency: "USD",
      #         credit_account_code: "1000", description?: "April salaries",
      #         entry_date?: "2025-04-30" }
      def payroll_entries
        period_str  = params[:period].to_s
        total       = params[:total_amount].to_s.to_d
        credit_code = (params[:credit_account_code].presence || "1000").to_s
        currency    = (params[:currency].presence || "EGP").upcase

        return render json: { error: { type: "invalid", detail: "period (YYYY-MM) required" } }, status: :unprocessable_entity \
          if period_str !~ /\A\d{4}-\d{2}\z/
        return render json: { error: { type: "invalid", detail: "total_amount must be > 0" } }, status: :unprocessable_entity \
          if total <= 0

        year, month = period_str.split("-").map(&:to_i)
        entry_date = params[:entry_date].present? ? Date.parse(params[:entry_date].to_s) : Date.new(year, month, -1)
        description = params[:description].presence || "Salaries — #{Date::MONTHNAMES[month]} #{year}"

        # Verify the credit account exists (Cash, AP, Accrued Liabilities…)
        unless Account.find_by(code: credit_code)
          return render json: { error: { type: "invalid", detail: "Unknown credit account #{credit_code}" } }, status: :unprocessable_entity
        end

        entry = JournalEntry.post!(
          {
            entry_date:  entry_date,
            description: description,
            currency:    currency,
            entry_type:  "manual",
            source_type: "Payroll",
            source_id:   period_str
          },
          [
            { account_code: "6000",       side: "debit",  amount: total, description: "Payroll expense #{period_str}" },
            { account_code: credit_code,  side: "credit", amount: total, description: "Payroll payment #{period_str}" }
          ]
        )

        AuditLog.record(user: current_user, action: "accounting.payroll.post",
                        subject: entry, request: request,
                        diff: { period: period_str, amount: total.to_s, credit: credit_code })

        render json: { data: JournalEntrySerializer.call(entry.reload, include_lines: true) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: { type: "invalid", detail: e.message } }, status: :unprocessable_entity
      end

      # POST /api/v1/accounting/journal_entries
      # Body: { entry_date:, description:, currency?: "USD", entry_type?: "manual",
      #         lines: [{ account_code:, side: "debit"|"credit", amount:, description? }, ...] }
      def create_journal_entry
        lines_attrs = Array(params[:lines]).map do |l|
          {
            account_code: l[:account_code],
            side:         l[:side],
            amount:       l[:amount].to_s.to_d,
            description:  l[:description]
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
