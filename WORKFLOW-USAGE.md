# Copilot Workflow Usage Guide
# คู่มือการใช้ Copilot สั่งงาน Workflow

> **Prerequisites / สิ่งที่ต้องมีก่อน:**
> Setup ตาม `WORKFLOW-BLUEPRINT.md` เสร็จแล้ว และมีไฟล์ `.env` ครบถ้วน

---

## 1. Start Working on Issues / เริ่มทำงาน Issue

**TH:** พิมพ์ใน Copilot Chat:
```
เริ่มทำ issue 5
เริ่มทำ issue 5 และ 7
start issue 5, 7, 9
```

**EN:** Type in Copilot Chat:
```
start issue 5
start working on issues 5 and 7
begin issue 5, 7, 9
```

**What happens / สิ่งที่เกิดขึ้น:**
- สร้าง branch `feat/issues-5-7-9` และ push ขึ้น remote
- อัปเดต issue #5, #7, #9 → **In Progress** ใน Project V2

---

## 2. Open a Pull Request / เปิด PR

**TH:** หลังจาก commit งานแล้ว พิมพ์ใน Copilot Chat:
```
เปิด PR สำหรับ issue 5, 7, 9
สร้าง PR ของ issue 5 และ 7
open pr for issue 5
```

**EN:**
```
open PR for issues 5, 7, 9
create a pull request for issue 5 and 7
open PR — issues 5, 7, 9
```

**What happens / สิ่งที่เกิดขึ้น:**
- สร้าง PR พร้อม body `Closes #5 / Closes #7 / Closes #9` อัตโนมัติ
- อัปเดต issue → **Code Review** ใน Project V2

---

## 3. Check Current Status / ดูสถานะงานปัจจุบัน

**TH:**
```
สถานะงานตอนนี้คืออะไร
กำลังทำ issue อะไรอยู่
```

**EN:**
```
what am I working on?
check current status
show my work status
```

**What happens / สิ่งที่เกิดขึ้น:**
- แสดง branch ปัจจุบัน, PR ที่เปิดอยู่, และ issue ที่ link

---

## 4. Update Status Manually / อัปเดต Status ด้วยตนเอง

**TH:**
```
เปลี่ยน issue 5 เป็น In Progress
อัปเดต issue 5, 7 เป็น Done
```

**EN:**
```
mark issue 5 as In Progress
update issue 5, 7 to Done
set issue 9 to Code Review
```

**Valid statuses:** `In Progress` / `Code Review` / `Done`

---

## 5. Full Day-to-Day Flow / ขั้นตอนการทำงานปกติ

```
TH                                    EN
──────────────────────────────────    ──────────────────────────────────
1. "เริ่มทำ issue 12, 15"            "start issues 12, 15"
   → branch สร้าง, status In Progress

2. (ทำงานจริง — แก้โค้ด, เพิ่มไฟล์)   (do actual work — edit code, files)

3. commit + push                      commit + push

4. "เปิด PR สำหรับ issue 12, 15"      "open PR for issues 12, 15"
   → PR สร้าง, status Code Review

5. (รอ review / merge)                (wait for review / merge)

6. (หลัง merge อัตโนมัติ)             (after merge — automatic)
   → status Done ✅                   → status Done ✅
```

---

## 6. UAT Deploy Tracking / ติดตาม Deploy UAT

### Setup (one-time) / ตั้งค่าครั้งแรก

```powershell
# Validate/create "UAT Deploy Version" and "UAT Deploy Status" fields, then write IDs to .env
.\tools\setup-uat-fields.ps1
```

หลังรันแล้ว ให้ copy ค่าที่ได้ไปตั้งเป็น **GitHub Repository Variables** ใน  
`Repo → Settings → Secrets and variables → Actions → Variables`

---

### Manual update / อัปเดต deploy status ด้วยตนเอง

```powershell
# Mark issues as deploying
.\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Status deploying

# Mark as success and record version
.\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Version "0.0.52" -Status success

# Mark as failed
.\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Status failed
```

---

### Automated via GitHub Actions / อัตโนมัติผ่าน Actions

เมื่อ merge PR → workflow `uat-deploy.yml` จะรันอัตโนมัติ:

```
PR Merged
  → UAT Deploy Status = Deploying
  → (fake deploy runs)
  → UAT Deploy Status = Success  + UAT Deploy Version = pr-{number}
     (or = Failed if workflow fails)
```

**Trigger manually with a specific version / สั่งรันด้วย version เอง:**  
GitHub → Actions → `UAT Deploy` → Run workflow → ใส่ `pr_number` + `version`

---

## 7. Tips / เคล็ดลับ

| TH | EN |
|----|----|
| ต้องเพิ่ม issue เข้า Project V2 ก่อนเสมอ | Always add issues to Project V2 first |
| ใช้ `open-pr.ps1` เสมอ — อย่าสร้าง PR ด้วยมือ | Always use `open-pr.ps1` — never create PR manually |
| PR body ต้องมี `Closes #X` จึงจะ auto-Done | PR body must have `Closes #X` for auto-Done to work |
| รัน `setup-uat-fields.ps1` ก่อนใช้ deploy tracking | Run `setup-uat-fields.ps1` before using deploy tracking |
| Copilot อ่าน issue number จาก chat ได้เลย | Copilot reads issue numbers directly from chat |
| พูดภาษาไทยหรืออังกฤษก็ได้ | Thai or English — both work |
