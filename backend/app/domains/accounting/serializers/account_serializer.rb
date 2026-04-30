class AccountSerializer
  def self.call(account)
    {
      id:           account.id,
      code:         account.code,
      name:         account.name,
      account_type: account.account_type,
      normal_side:  account.normal_side,
      currency:     account.currency,
      active:       account.active,
      description:  account.description
    }
  end
end
