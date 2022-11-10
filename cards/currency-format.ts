export function balanceInCurrency(
  balance: number,
  exchangeRate: number,
  currency: string
) {
  if (balance == null || exchangeRate == null) {
    return 0;
  }
  let total = balance * exchangeRate;
  if (currency === "USD") {
    return formatUSD(total);
  } else {
    return `${Number.isInteger(total) ? total : total.toFixed(2)} ${currency}`;
  }
}

export function formatUSD(amount: number) {
  if (amount == null) {
    amount = 0;
  }
  return `$ ${amount.toFixed(2)} USD`;
}
