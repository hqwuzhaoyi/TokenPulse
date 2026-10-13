#!/usr/bin/env python3
"""Read-only localization preflight; writes only the explicitly authorized scratch report/JSON.
Not a Swift compiler, native extraction replacement, runtime/VoiceOver test or ticket-10 sign-off.
"""
from pathlib import Path
from collections import defaultdict
import json, re, subprocess, datetime, hashlib
ROOT=Path.cwd()
SCRATCH=ROOT/'.scratch/internationalization'
CATALOG=ROOT/'TokenPulse/Resources/Localizable.xcstrings'
cat_doc=json.loads(CATALOG.read_text()); catalog=cat_doc['strings']
roots=['TokenPulse','TokenPulseWatch','TokenPulseWidgets','TokenPulseWatchWidgets']
files=sorted(p for name in roots for p in (ROOT/name).rglob('*.swift'))


def production_mask(source):
    stack=[];out=[];debug_lines=set()
    for n,line in enumerate(source.splitlines(True),1):
        stripped=line.strip()
        if stripped.startswith('#if '):
            cond=stripped[4:].strip();stack.append({'debug': bool(re.search(r'\bDEBUG\b',cond)) and not bool(re.search(r'!\s*DEBUG',cond)), 'debug_cond':bool(re.search(r'\bDEBUG\b',cond))})
        elif stripped.startswith('#else') and stack and stack[-1]['debug_cond']: stack[-1]['debug']=not stack[-1]['debug']
        elif stripped.startswith('#endif') and stack: stack.pop()
        is_debug=any(item['debug'] for item in stack)
        if is_debug: debug_lines.add(n)
        out.append(''.join('\n' if c=='\n' else ' ' for c in line) if is_debug else line)
    return ''.join(out),debug_lines

# Small lexer: recognizes comments, Swift raw/multiline strings and nested interpolation.
# Native stringsdata remains the authority for compiler-recognized UI keys.
def lex_strings(source):
    tokens=[]
    def parse_string(start):
        hashes=0;i=start
        while i<len(source) and source[i]=='#':hashes+=1;i+=1
        if i>=len(source) or source[i]!='"':return None
        triple=source.startswith('"""',i);opening='"""' if triple else '"';closing=opening+'#'*hashes
        i+=len(opening);parts=[];interpolated=False
        while i<len(source):
            if source.startswith(closing,i):
                end=i+len(closing);value=''.join(parts)
                value=re.sub(r'\\u\{([0-9a-fA-F]+)\}',lambda m:chr(int(m[1],16)),value)
                for a,b in [('\\n','\n'),('\\r','\r'),('\\t','\t'),('\\"','"'),('\\\\','\\')]:value=value.replace(a,b)
                token={'start':start,'end':end,'value':value,'interpolated':interpolated,'line':source.count('\n',0,start)+1}
                tokens.append(token);return token
            escape='\\'+'#'*hashes
            if source.startswith(escape+'(',i):
                interpolated=True;parts.append('%@');i+=len(escape)+1;depth=1
                while i<len(source) and depth:
                    inner=parse_string(i)
                    if inner:i=inner['end'];continue
                    if source[i]=='(':depth+=1
                    elif source[i]==')':depth-=1
                    i+=1
                continue
            if hashes==0 and source[i]=='\\' and i+1<len(source):parts.append(source[i:i+2]);i+=2;continue
            parts.append(source[i]);i+=1
        return None
    i=0
    while i<len(source):
        if source.startswith('//',i):
            n=source.find('\n',i);i=len(source) if n<0 else n+1;continue
        if source.startswith('/*',i):
            depth=1;i+=2
            while i<len(source) and depth:
                if source.startswith('/*',i):depth+=1;i+=2
                elif source.startswith('*/',i):depth-=1;i+=2
                else:i+=1
            continue
        parsed=parse_string(i)
        i=parsed['end'] if parsed else i+1
    return sorted(tokens,key=lambda t:t['start'])

placeholder=re.compile(r'%(?:(\d+)\$)?[-+#0 ]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|ll|h|l|L|z|t|j)?([@diuoxXfFeEgGaAcCsSp])')
def signature(s):
    result={};index=1
    for m in placeholder.finditer(s.replace('%%','')):
        position=int(m[1]) if m[1] else index
        if not m[1]:index+=1
        result[position]=(m[2] or '')+m[3]
    return result

def string_units(node,path=()):
    if isinstance(node,dict):
        if 'stringUnit' in node:yield path,node['stringUnit']
        for k,v in node.items():
            if k!='stringUnit':yield from string_units(v,path+(k,))

catalog_errors=[];plural_keys=[]
for key,entry in catalog.items():
    for lang in ['en','zh-Hans']:
        localized=entry.get('localizations',{}).get(lang)
        if not localized:catalog_errors.append((key,lang,'missing localization'));continue
        units=list(string_units(localized))
        if not units:catalog_errors.append((key,lang,'missing stringUnit'))
        if 'variations' in localized:
            plural=localized.get('variations',{}).get('plural',{})
            if plural and 'other' not in plural:catalog_errors.append((key,lang,'plural has no other'))
            if plural and lang=='en' and 'one' not in plural:catalog_errors.append((key,lang,'English plural has no one'))
            if plural:plural_keys.append(key)
        for path,unit in units:
            if unit.get('state')!='translated':catalog_errors.append((key,lang,'non-translated state',unit.get('state')))
            if signature(key)!=signature(unit.get('value','')):catalog_errors.append((key,lang,'interpolation signature mismatch',str(path),signature(key),signature(unit.get('value',''))))

# Parse current Xcode project with the platform parser; no project conversion is written to disk.
project=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(ROOT/'TokenPulse.xcodeproj/project.pbxproj')]))
objects=project['objects'];membership={}
for _,target in objects.items():
    if target.get('isa')!='PBXNativeTarget' or target.get('name') not in roots:continue
    refs=[]
    for phase in target['buildPhases']:
        p=objects[phase]
        if p.get('isa')=='PBXResourcesBuildPhase':
            for build_id in p.get('files',[]):
                file_ref=objects[build_id].get('fileRef');path=objects.get(file_ref,{}).get('path')
                if path and path.endswith('.xcstrings'):refs.append((build_id,file_ref,path))
    membership[target['name']]=refs

source_data={}
for p in files:
    source=p.read_text();production,debug_lines=production_mask(source)
    source_data[str(p)]={'source':source,'production':production,'debug_lines':debug_lines,'tokens':lex_strings(production)}

native=defaultdict(list);debug_native=defaultdict(list);native_counts=defaultdict(lambda: {'artifacts':0,'rows':0,'keys':set(),'sources':set()});location_issues=[]
intermediates=Path('/tmp/tokenpulse-i18n-build/Build/Intermediates.noindex/TokenPulse.build')
artifact_candidates=list(intermediates.rglob('*.stringsdata'))
latest_artifacts={}
for p in artifact_candidates:
    data=json.loads(p.read_text());source=data.get('source')
    target=next((part[:-6] for part in reversed(p.parts) if part.endswith('.build') and part[:-6] in roots),'unknown')
    pair=(source,target)
    if pair not in latest_artifacts or p.stat().st_mtime > latest_artifacts[pair].stat().st_mtime: latest_artifacts[pair]=p
for p in latest_artifacts.values():
    data=json.loads(p.read_text());source=data.get('source')
    if source not in source_data:continue
    target=next((part[:-6] for part in reversed(p.parts) if part.endswith('.build') and part[:-6] in roots),'unknown')
    native_counts[target]['artifacts']+=1
    for table,rows in data.get('tables',{}).items():
        for row in rows:
            key=row['key'];line=row.get('location',{}).get('startingLine',0);item={'file':str(Path(source).relative_to(ROOT)),'line':line,'target':target,'artifact':str(p)}
            if line in source_data[source]['debug_lines']:debug_native[key].append(item);continue
            native[key].append(item);native_counts[target]['rows']+=1;native_counts[target]['keys'].add(key);native_counts[target]['sources'].add(source)
            lines=source_data[source]['source'].splitlines()
            if line<1 or line>len(lines):location_issues.append(item)

# Enumerate real L10n calls, including ternary key alternatives and argument counts.
def split_top(source,start,end,separator=','):
    result=[];chunk=start;stack=[];quotes=lex_strings(source[start:end]);qmap={t['start']+start:t['end']+start for t in quotes};i=start
    while i<end:
        if i in qmap:i=qmap[i];continue
        c=source[i]
        if c in '([{':stack.append(c)
        elif c in ')]}':
            if stack:stack.pop()
        elif c==separator and not stack:result.append((chunk,i));chunk=i+1
        i+=1
    result.append((chunk,end));return result

def alternatives(expr):
    expr=expr.strip()
    while expr.startswith('(') and expr.endswith(')'):expr=expr[1:-1].strip()
    qmap={t['start']:t['end'] for t in lex_strings(expr)};stack=[];question=None;ternary=0;i=0
    while i<len(expr):
        if i in qmap:i=qmap[i];continue
        c=expr[i]
        if c in '([{':stack.append(c)
        elif c in ')]}':
            if stack:stack.pop()
        elif not stack:
            if c=='?' and (i+1>=len(expr) or expr[i+1] not in '?.') and (i==0 or expr[i-1]!='?'):
                if question is None:question=i
                ternary+=1
            elif c==':' and question is not None:
                ternary-=1
                if ternary==0:return alternatives(expr[question+1:i])+alternatives(expr[i+1:])
        i+=1
    t=lex_strings(expr)
    if len(t)==1 and t[0]['start']==0 and t[0]['end']==len(expr):return [(t[0]['value'],t[0]['interpolated'])]
    return []

l10n_keys=defaultdict(list);unbounded=[];format_count_errors=[];call_count=0
for p in files:
    s=source_data[str(p)]['production'];tokens=source_data[str(p)]['tokens'];qmap={t['start']:t['end'] for t in tokens}
    for m in re.finditer(r'\bL10n\.(text|format)\s*\(',s):
        # Avoid mentions inside string values.
        if any(t['start']<=m.start()<t['end'] for t in tokens):continue
        start=m.end();i=start;depth=1
        while i<len(s) and depth:
            if i in qmap:i=qmap[i];continue
            if s[i]=='(':depth+=1
            elif s[i]==')':depth-=1
            i+=1
        end=i-1;args=split_top(s,start,end);key_expr=s[args[0][0]:args[0][1]];keys=alternatives(key_expr)
        where={'file':str(p.relative_to(ROOT)),'line':s.count('\n',0,m.start())+1,'method':m[1],'expression':key_expr.strip()};call_count+=1
        if not keys:unbounded.append(where);continue
        argc=sum(not re.match(r'\s*(language|locale)\s*:',s[a:b]) for a,b in args[1:])
        for key,interpolated in keys:
            l10n_keys[key].append(where)
            if interpolated:format_count_errors.append((where,'interpolated lookup key',key))
            if m[1]=='format' and max(signature(key),default=0)!=argc:format_count_errors.append((where,'argument count',key,argc,signature(key)))

fragment_keys=set();fragment_results={};fragment_diffs=[]
for p in sorted((SCRATCH/'fragments').glob('*.json')):
    data=json.loads(p.read_text());fragment_results[p.name]={'count':len(data),'missing':[]}
    for key,value in data.items():
        fragment_keys.add(key)
        if key not in catalog:fragment_results[p.name]['missing'].append(key);continue
        en=catalog[key].get('localizations',{}).get('en',{})
        if isinstance(value,str):
            actual=en.get('stringUnit',{}).get('value')
            if actual!=value:fragment_diffs.append((p.name,key,value,actual))
        else:
            for lang,translation in value.get('localizations',{}).items():
                if catalog[key].get('localizations',{}).get(lang)!=translation:fragment_diffs.append((p.name,key,'full entry differs',lang))

native_missing={k:v for k,v in native.items() if k not in catalog}
l10n_missing={k:v for k,v in l10n_keys.items() if k not in catalog}
# Manual review queue: Chinese source literals not represented by a catalog key.
# Includes raw API-owned labels, immutable identity tokens and comparison suffixes; not all are omissions.
chinese_review=[]
for p in files:
    for token in source_data[str(p)]['tokens']:
        v=token['value']
        if any('\u4e00'<=c<='\u9fff' for c in v) and v not in catalog:
            chinese_review.append({'file':str(p.relative_to(ROOT)),'line':token['line'],'text':v,'interpolated':token['interpolated']})

result={'timestamp':datetime.datetime.now().isoformat(),'catalog_count':len(catalog),'catalog_sha256':hashlib.sha256(CATALOG.read_bytes()).hexdigest(),'production_swift_files':len(files),'catalog_errors':catalog_errors,'plural_keys':sorted(set(plural_keys)),'membership':membership,'native_counts':{k:{**v,'keys':len(v['keys']),'sources':len(v['sources'])} for k,v in native_counts.items()},'native_distinct_keys':len(native),'native_missing':native_missing,'debug_native_keys':debug_native,'native_location_issues':location_issues,'l10n_call_count':call_count,'l10n_distinct_literal_keys':len(l10n_keys),'l10n_missing':l10n_missing,'unbounded_l10n_calls':unbounded,'format_count_errors':format_count_errors,'fragment_results':fragment_results,'fragment_distinct_keys':len(fragment_keys),'fragment_diffs':fragment_diffs,'chinese_review':chinese_review}
# Manual finite-domain ledger is independently reviewed; verify every current variable
# call is represented and its closed resource key list/signatures remain valid.
manual_path=SCRATCH/'10-coverage-manual-review.json'
manual_errors=[]
if manual_path.exists():
    manual=json.loads(manual_path.read_text())
    identity=lambda item:(item['file'],item['line'],item['method'],item['expression'])
    records={identity(item):item for item in manual.get('variable_lookups',[])}
    for item in unbounded:
        record=records.get(identity(item))
        if record is None: manual_errors.append([item,'manual finite-domain review missing']);continue
        for key in record.get('verified_catalog_keys',[]):
            if key not in catalog:manual_errors.append([item,'finite-domain key missing',key])
            elif item['method']=='format' and max(signature(key),default=0)!=1:
                manual_errors.append([item,'finite-domain format expected one numeric/string argument',key])
    for item_id in records.keys()-{identity(item) for item in unbounded}:
        manual_errors.append([item_id,'manual ledger stale call'])
result['manual_domain_errors']=manual_errors
result['manual_domain_reviewed_calls']=len(unbounded)-sum('manual finite-domain review missing' in str(item) for item in manual_errors)
(SCRATCH/'10-coverage-preflight.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['catalog_count','production_swift_files','catalog_errors','membership','native_counts','native_distinct_keys','native_missing','l10n_call_count','l10n_distinct_literal_keys','l10n_missing','format_count_errors','fragment_results','fragment_diffs','manual_domain_errors','manual_domain_reviewed_calls']},ensure_ascii=False,indent=2))
print('manual review: unbounded lookups',len(unbounded),'Chinese source tokens',len(chinese_review),'debug native keys',len(debug_native))
