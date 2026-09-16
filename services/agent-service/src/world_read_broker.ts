import {randomUUID} from "node:crypto";
import type {DecisionRequest} from "./protocol.ts";

export class WorldReadBroker {
  #pending=new Map<string,{request:DecisionRequest;resolve:(v:Record<string,unknown>)=>void;reject:(e:Error)=>void}>();
  async read(request:DecisionRequest,name:string,args:Record<string,unknown>,emit:(payload:unknown)=>void,signal?:AbortSignal):Promise<Record<string,unknown>>{
    signal?.throwIfAborted();
    const read_id=randomUUID();
    return new Promise((resolve,reject)=>{
      let timer:ReturnType<typeof setTimeout>;
      const finish=(value?:Record<string,unknown>,error?:Error)=>{clearTimeout(timer);this.#pending.delete(read_id);signal?.removeEventListener("abort",cancel);error?reject(error):resolve(value!);};
      const cancel=()=>finish(undefined,new Error("read_cancelled"));
      this.#pending.set(read_id,{request,resolve:v=>finish(v),reject:e=>finish(undefined,e)});
      timer=setTimeout(()=>finish({ok:false,error:"temporarily_unavailable",read_id}),5000);
      signal?.addEventListener("abort",cancel,{once:true});
      emit({read_id,request_id:request.request_id,session_id:request.session_id,session_epoch:request.session_epoch,agent_id:request.agent_id,name,arguments:args});
    });
  }
  accept(value:Record<string,unknown>):boolean{
    const pending=this.#pending.get(String(value.read_id));
    if(!pending)return false;
    if(["request_id","session_id","session_epoch","agent_id"].some(k=>value[k]!==pending.request[k as keyof DecisionRequest]))throw new Error("read_scope_mismatch");
    if(!value.result||typeof value.result!=="object"||Array.isArray(value.result))throw new Error("invalid_read_result");
    pending.resolve(value.result as Record<string,unknown>);return true;
  }
}
