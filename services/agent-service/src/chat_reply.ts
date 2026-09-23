import { replyContent } from "./chat/reply_content.ts";

// Some local chat models echo their setup before answering. Only recognized
// leading metadata is removed; ordinary headings and the reply body stay intact.
const labels=["角色背景","角色设定","人物设定","角色信息","你的身份","你是","当前场景","场景设定","系统提示词","系统提示","System prompt","Character background","Character profile","Current scene"];
const background="你与玩家生活在农庄村落。";
const escape=(text:string)=>text.replace(/[.*+?^${}()|[\]\\]/g,"\\$&");
const metadata=new RegExp(`^(?:#{1,6}[ \\t]*)?(?:${labels.map(escape).join("|")})(?:[：:]|[ \\t]*(?:\\r?\\n|$))` ,"i");

export function chatReplyText(raw:string,complete=true):string {
  let text=raw.trimStart();
  for(let pass=0;pass<24;pass++){
    text=replyContent(text,complete).trimStart();
    // Older models sometimes emit the chat-history envelope (even nested).
    const wrapper=/^\{\s*"(?:speaker|text)"\s*:/.test(text);
    if(wrapper){
      try{
        const value=JSON.parse(text);
        if(value&&typeof value.speaker==="string"&&typeof value.text==="string"&&Object.keys(value).every(k=>["speaker","text"].includes(k))){text=value.text.trimStart();continue;}
      }catch{return "";}
    }
    if(!complete && /^\{\s*"?(?:s(?:p(?:e(?:a(?:k(?:e(?:r)?)?)?)?)?)?|t(?:e(?:x(?:t)?)?)?)?"?\s*$/.test(text))return "";
    const firstLine=text.split(/\r?\n/,1)[0];
    const heading=firstLine.replace(/^#{1,6}[ \t]*/,"");
    const known=metadata.test(text)||/^#{1,6}[ \t]*/.test(text)&&heading===background;
    if(known){
      const end=/\r?\n[ \t]*\r?\n/.exec(text);
      if(!end)return "";
      // A label-only heading has its metadata paragraph on the following line.
      const labelOnly=labels.some(label=>heading.replace(/[：:]\s*$/,"").trim().toLowerCase()===label.toLowerCase());
      text=text.slice(end.index+end[0].length).trimStart();
      if(labelOnly&&text&&!metadata.test(text)){
        const paragraph=/\r?\n[ \t]*\r?\n/.exec(text);
        if(!paragraph)return "";
        text=text.slice(paragraph.index+paragraph[0].length).trimStart();
      }
      continue;
    }
    // Hold only an unfinished candidate heading, so it cannot flash in the UI.
    if(!complete&&!text.includes("\n")){
      const candidate=heading.toLowerCase();
      if(/^#{1,6}[ \t]*$/.test(text)||labels.some(label=>label.toLowerCase().startsWith(candidate))||/^#/.test(text)&&background.startsWith(heading))return "";
    }
    break;
  }
  return complete?text.trim():text.replace(/[\uD800-\uDBFF]$/, "");
}
