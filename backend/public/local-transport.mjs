// WebSocket-shaped local adapter; no network connection or persisted room token.
export class LocalTransport {
  constructor(){
    this.readyState=0;
    this.worker=new Worker(new URL('./solo-worker.mjs',import.meta.url),{type:'module',name:'Tank Battle offline simulation'});
    this.worker.onmessage=({data})=>{
      if(this.readyState===3)return;
      if(data.type==='ready'){this.readyState=1;this.onopen?.();}
      else this.onmessage?.({data:JSON.stringify(data)});
    };
    this.worker.onerror=()=>{this.onerror?.();this.close();};
  }
  send(raw){if(this.readyState===1)this.worker.postMessage(JSON.parse(raw));}
  close(){if(this.readyState===3)return;this.readyState=3;this.worker.terminate();this.onclose?.();}
}
