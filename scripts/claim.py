import urllib.request, json
from brownie import Contract, accounts, web3
import click
import json


def main():
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    merkleOrchard = Contract("0xdAE7e32ADc5d490a43cCba1f0c736033F2b4eFca")
    bal = "0xba100000625a3754423978a60c9317c58a424e3D"
    ldo = "0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32"
    bal_distributor = "0xd2EB7Bd802A7CA68d9AcD209bEc4E664A9abDD7b"
    # ldo_distributor = "" use legacy claim. Orchard not set up yet for ldo
    rewards = [("homestead.json", bal, bal_distributor, "BAL")]
    # ("homestead-lido.json", ldo, ldo_distributor, "LDO")

    for reward in rewards:
        f = open(f'./scripts/{reward[0]}', )
        data = json.load(f)
        config = data["config"]
        tokens_data = data["tokens_data"]
        distributionId = config["week"] - config["offset"]

        for token_data in tokens_data:
            claim = [(distributionId,
                      int(token_data["claim_amount"]),
                      reward[2],
                      0,
                      token_data["hex_proof"])]
            merkleOrchard.claimDistributions(token_data["address"], claim, [reward[1]], {'from': dev})
            print(f'{token_data["address"]} claimed {int(token_data["claim_amount"]) / 1e18} {reward[3]} ')
