import jsonlines

markets = []

with jsonlines.open("./markets.jsonl") as f:
    markets = list(f)
    
print(markets)

trades = []

for market in markets:
    exports = map(lambda ex: ex["symbol"], market["exports"])

    buy_trade_goods = market["tradeGoods"]

    for export in exports:
        for possible_market in markets:
            possible_imports = map(lambda im: im["symbol"], possible_market["imports"])

            if export in possible_imports:
                print(f"{export} from {market['symbol']} to {possible_market['symbol']}")

                sell_trade_goods = possible_market["tradeGoods"]

                buy_price = 0
                sell_price = 0

                for x in buy_trade_goods:
                    if x["symbol"] == export:
                        buy_price = x["purchasePrice"]

                for x in sell_trade_goods:
                    if x["symbol"] == export:
                        sell_price = x["sellPrice"]

                profit_per_unit = sell_price - buy_price
                margin = sell_price / buy_price

                print(f"Buy at {buy_price}")
                print(f"Sell at {sell_price}")
                print(f"Profit per unit: {profit_per_unit}")
                print(f"Margin: {margin}")

                trades.append({
                    "from": market["symbol"],
                    "to": possible_market["symbol"],
                    "symbol": export,
                    "buy_price": buy_price,
                    "sell_price": sell_price,
                    "profit_per_unit": profit_per_unit,
                    "margin": margin,
                })

best = None

for trade in trades:
    if best == None:
        best = trade
        continue

    if best["profit_per_unit"] < trade["profit_per_unit"]:
        best = trade

print(best)
