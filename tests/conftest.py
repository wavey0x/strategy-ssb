import pytest
from brownie import config
from brownie import Contract


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)


@pytest.fixture
def user(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]


@pytest.fixture
def token():
    # 0x6B175474E89094C44Da98b954EedeAC495271d0F DAI
    # 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 USDC
    # 0xdAC17F958D2ee523a2206206994597C13D831ec7 USDT
    token_address = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
    yield Contract(token_address)


@pytest.fixture
def amount(accounts, token, user):
    amount = 1_000_000 * 10 ** token.decimals()
    # In order to get some funds for the token you are about to use,
    # 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643 DAI
    # 0x0A59649758aa4d66E25f08Dd01271e891fe52199 USDC
    # 0xA929022c9107643515F5c777cE9a910F0D1e490C USDT
    reserve = accounts.at("0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643", force=True)
    token.transfer(user, amount, {"from": reserve})
    yield amount


@pytest.fixture
def weth():
    token_address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    yield Contract(token_address)


@pytest.fixture
def bal():
    token_address = "0xba100000625a3754423978a60c9317c58a424e3D"
    yield Contract(token_address)


@pytest.fixture
def bal_whale(accounts):
    yield accounts.at("0xBA12222222228d8Ba445958a75a0704d566BF2C8", force=True)


@pytest.fixture
def ldo():
    token_address = "0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32"
    yield Contract(token_address)


@pytest.fixture
def ldo_whale(accounts):
    yield accounts.at("0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c", force=True)


@pytest.fixture
def weth_amout(user, weth):
    weth_amout = 10 ** weth.decimals()
    user.transfer(weth, weth_amout)
    yield weth_amout


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, management, {"from": gov})
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture
def balancer_vault():
    yield Contract("0xBA12222222228d8Ba445958a75a0704d566BF2C8")


@pytest.fixture
def pool():
    address = "0x06Df3b2bbB68adc8B0e302443692037ED9f91b42"
    yield Contract(address)


@pytest.fixture
def strategy(strategist, keeper, vault, Strategy, gov, balancer_vault, pool, bal, ldo):
    strategy = strategist.deploy(Strategy, vault, balancer_vault, pool, 10, 10, 100_000, 2 * 60 * 60)
    strategy.setKeeper(keeper)
    strategy.whitelistRewards(bal, {'from': gov})
    strategy.whitelistRewards(ldo, {'from': gov})
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    # making this more lenient bc of single sided deposits incurring slippage
    yield 1e-3
