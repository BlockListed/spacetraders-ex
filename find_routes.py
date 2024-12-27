import jsonlines

markets = []

with jsonlines.open("./markets.jsonl") as f:
    markets = list(f)
    
print(markets)

trades = []

for market in markets:
    exports = map(lambda ex: ex["symbol"], market["data"]["exports"])

    buy_trade_goods = market["data"]["tradeGoods"]

    for export in exports:
        for possible_market in markets:
            possible_imports = map(lambda im: im["symbol"], possible_market["data"]["imports"])

            if export in possible_imports:
                print(f"{export} from {market['waypoint']} to {possible_market['waypoint']}")

                sell_trade_goods = possible_market["data"]["tradeGoods"]

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
                    "from": market["waypoint"],
                    "to": possible_market["waypoint"],
                    "symbol": export,
                    "buy_price": buy_price,
                    "sell_price": sell_price,
                    "profit_per_unit": profit_per_unit,
                    "margin": margin,
                })

cheapest = None

for trade in trades:
    if cheapest == None:
        cheapest = trade
        continue

    if cheapest["profit_per_unit"] < trade["profit_per_unit"]:
        cheapest = trade

print(cheapest)