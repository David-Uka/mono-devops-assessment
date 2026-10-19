import { Get, JsonController, NotFoundError, QueryParam } from "routing-controllers";
import { Service } from "typedi";
import type { Account } from "../interfaces/account.ts";
import { AccountService } from "../services/account.service.js";

@Service()
@JsonController("/getAccount")
export class AccountController {
  constructor(private readonly accountService: AccountService) {}

  @Get()
  getAccount(@QueryParam("id") id?: string): Account | { count: number; accounts: Account[] } {
    if (id === undefined) {
      const accounts = this.accountService.findAll();
      return { count: accounts.length, accounts };
    }

    const account = this.accountService.findById(id);
    if (!account) {
      throw new NotFoundError(`Account with id '${id}' not found`);
    }
    return account;
  }
}
