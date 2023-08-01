const { expect } = require("chai");
const { Console } = require("console");
const { ethers } = require("hardhat");

describe("Test Start...\n", function () {

    let stackz
    let tokn
    let owner
    let addr1
    let adrs2

    

    it ("👆Deploys...", async function () {
        owner = await ethers.getSigner(0);
        addr1 = await ethers.getSigner(1);
        
        const Tokenz = await ethers.getContractFactory("TestToken");
        tokn = await Tokenz.deploy();
        await tokn.deployed();
        console.log('Test token deployed')
        
        const Stackz = await ethers.getContractFactory("StakingContract");
        stackz = await Stackz.deploy(tokn.address);
        await stackz.deployed();
        console.log('Stack deployed')
        let balOwner = await tokn.balanceOf(owner.address)
        let half = balOwner.div(2)
        await tokn.approve(stackz.address, half)
        await stackz.addToStakingPool(half)
        console.log("stack funded ",half.toString())
        expect(await stackz.stakingPool()).to.equal(half)

        await tokn.transfer(addr1.address, "100000000000000000000")

    })

    it("", async function () {console.log("----- FUNCTION TESTS: emergencyUnstake, withdrawReward & unstack, unstake -----")} )

    it ("👆test emergencyUnstake after 1day", async function () {
        console.log("Staking 100e18 tokens for 90 days")
        await tokn.connect(addr1).approve(stackz.address, "100000000000000000000")
        /* console.log("Balance before: ",(await tokn.balanceOf(addr1.address)).toString()) */
        await stackz.connect(addr1).stake("100000000000000000000",25,86400*90)
        expect(await stackz.totalStaked()).to.equal("100000000000000000000")
        console.log("1 day later...")
        await ethers.provider.send("evm_increaseTime", [86400])
        await ethers.provider.send("evm_mine")
        console.log("--emergencyUnstake--")
        await stackz.connect(addr1).emergencyUnstake()/* 
        console.log("Balance after (with penalty): ",(await tokn.balanceOf(addr1.address)).toString()) */

    })

    it ("👆test withdrawReward & unstack", async function () {
        console.log("staking 100e18 tokens for 90 days")
        await tokn.connect(owner).transfer(addr1.address, "100000000000000000000")
        await tokn.connect(addr1).approve(stackz.address, "100000000000000000000")
        
        await stackz.connect(addr1).stake("100000000000000000000",25,86400*90)
        console.log("45 day later...")
        await ethers.provider.send("evm_increaseTime", [86400*45])
        await ethers.provider.send("evm_mine")
        console.log("withdrawReward")
        await stackz.connect(addr1).withdrawReward()

        await ethers.provider.send("evm_increaseTime", [86400*45])
        await ethers.provider.send("evm_mine")
        console.log("45 day later...\nUnstake")
        await stackz.connect(addr1).unstake()

    })
    it ("👆test unstake", async function () {
        console.log("Staking 100e18 tokens for 90 days")
        await tokn.connect(owner).transfer(addr1.address, "100000000000000000000")
        await tokn.connect(addr1).approve(stackz.address, "100000000000000000000")
        await stackz.connect(addr1).stake("100000000000000000000",25,86400*90)
        console.log("90 day later...")
        await ethers.provider.send("evm_increaseTime", [86400*90])
        await ethers.provider.send("evm_mine")
        console.log("Unstake..")
        await stackz.connect(addr1).unstake()
    })
    it("", async function () {console.log("----- CERTIK 3 TEST CASES -----")})
    
    it("👆certik test case1 - emergency unstack 2 month after", async function () {
       
        adrs2 = await ethers.getSigner(2);
        await tokn.connect(owner).transfer(adrs2.address, "100000000000000000000")
        await tokn.connect(adrs2).approve(stackz.address, "100000000000000000000")
        await stackz.connect(adrs2).stake("100000000000000000000",25,86400*(30*12))
        await ethers.provider.send("evm_increaseTime", [86400*60])
        await ethers.provider.send("evm_mine")
        await stackz.connect(adrs2).emergencyUnstake()
        let poolBVar = await stackz.stakingPool()
        expect(await tokn.balanceOf(stackz.address)).to.equal(poolBVar)
        console.log("balanceOf stack",(await tokn.balanceOf(stackz.address)).toString())
        console.log("stakingPool: ",poolBVar.toString())
        console.log("tokn.balanceOf(stack.address) == stack.stakingPool()",true)
    })

    
    it("👆certik test case2 - emergency unstack 6 month after", async function () {
        let adrs2 = await ethers.getSigner(4);
        await tokn.connect(owner).transfer(adrs2.address, "100000000000000000000")
        await tokn.connect(adrs2).approve(stackz.address, "100000000000000000000")
        await stackz.connect(adrs2).stake("100000000000000000000",25,86400*(30*12))
        await ethers.provider.send("evm_increaseTime", [86400*60])
        await ethers.provider.send("evm_mine")

        let poolBVar = await stackz.stakingPool()
        expect(await tokn.balanceOf(stackz.address)).to.equal(poolBVar)
        console.log("balanceOf stack",(await tokn.balanceOf(stackz.address)).toString())
        console.log("stakingPool: ",poolBVar.toString())
        console.log("tokn.balanceOf(stack.address) == stack.stakingPool()",true)
    })
    it("👆certik test case3 - emergency unstack 10 month after", async function () {
        let adrs2 = await ethers.getSigner(3);
        await tokn.connect(owner).transfer(adrs2.address, "100000000000000000000")
        await tokn.connect(adrs2).approve(stackz.address, "100000000000000000000")
        await stackz.connect(adrs2).stake("100000000000000000000",25,86400*(30*12))
        await ethers.provider.send("evm_increaseTime", [86400*60])
        await ethers.provider.send("evm_mine")


        let poolBVar = await stackz.stakingPool()
        expect(await tokn.balanceOf(stackz.address)).to.equal(poolBVar)
        console.log("balanceOf stack",(await tokn.balanceOf(stackz.address)).toString())
        console.log("stakingPool: ",poolBVar.toString())
        console.log("tokn.balanceOf(stack.address) == stack.stakingPool()",true)

    })


    it("👆Random test [100users,50 3m, 25 6m, 25 12m]", async function () {
        let users3m = []
        let users6m = []
        let users12m = []
        for (let i = 0; i < 100; i++) {
            const randUser = await ethers.getSigner(i+5);
            await tokn.connect(owner).transfer(randUser.address, "100000000000000000000")
            await tokn.connect(randUser).approve(stackz.address, "100000000000000000000")
            if(i<50){
                
                await stackz.connect(randUser).stake("100000000000000000000",25,86400*(30*3))
                //console.log(i,"staked 3m", randUser.address) /// si 50
                users3m.push(randUser)
            }else if(i<75){
                await stackz.connect(randUser).stake("100000000000000000000",25,86400*(30*6))
                //console.log(i,"staked 6m")
                
                users6m.push(randUser)
            }else{
                await stackz.connect(randUser).stake("100000000000000000000",25,86400*(30*12))
                //console.log(i,"staked 12m")
                users12m.push(randUser)
            }
        }
        await ethers.provider.send("evm_increaseTime", [86400*60])
        await ethers.provider.send("evm_mine")
        console.log("60day later ----- 90 WITHDRAW REWARD & 10 EMERGENCY UNSTAK -----")

        for (let i = 0; i < users3m.length; i++) {
            await stackz.connect(users3m[i]).withdrawReward()
            //console.log(i,"withdrawReward 3m")
        }
        for (let i = 0; i < users6m.length; i++) {
            await stackz.connect(users6m[i]).withdrawReward()
            //console.log(i,"withdrawReward 6m")
        }
        for (let i = 0; i < users12m.length; i++) {
            await stackz.connect(users12m[i]).withdrawReward()
            if(i == 9){
                await stackz.connect(users12m[i]).emergencyUnstake()
                //console.log(i,"emergencyUnstake 12m")
                users12m.splice(i,1)
            }
        }
        await ethers.provider.send("evm_increaseTime", [86400*30])
        await ethers.provider.send("evm_mine")
        console.log("30 more day later ----- 3m UNSTAK -----")

        for (let i = 0; i < users3m.length; i++) {
            await stackz.connect(users3m[i]).unstake()
            //console.log(i,"unstake 3m")
        }
        await ethers.provider.send("evm_increaseTime", [86400*90])
        await ethers.provider.send("evm_mine")
        console.log("90 more day later ----- 25 UNSTAK & 15 WITHDRAW-----")

        for (let i = 0; i < users6m.length; i++) {
            await stackz.connect(users6m[i]).unstake()
            //console.log(i,"unstake 6m")
        }
        for (let i = 0; i < users12m.length; i++) {
            await stackz.connect(users12m[i]).withdrawReward()
            //console.log(i,"withdrawReward 12m")
        }
        await ethers.provider.send("evm_increaseTime", [86400*180])
        await ethers.provider.send("evm_mine")
        console.log("180 more day later ----- LAST 15 UNSTACK-----")

        for (let i = 0; i < users12m.length; i++) {
            //console.log(i,"unstake 12m")
            //let a = await stackz.stakers(users12m[i].address)
            //let blocktime = await ethers.provider.getBlock("latest")
            //console.log("blocktime ",blocktime.timestamp)
            //console.log("endtime ",parseInt(a[1]) , parseInt(a[5]), parseInt(a[1]) + parseInt(a[5]))
            await stackz.connect(users12m[i]).unstake()
            
        }
        let poolBVar = await stackz.stakingPool()
        expect(await tokn.balanceOf(stackz.address)).to.equal(poolBVar)
        console.log("DONE")

    })

});