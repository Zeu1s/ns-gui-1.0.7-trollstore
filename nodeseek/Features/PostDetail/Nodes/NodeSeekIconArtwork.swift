//
//  NodeSeekIconArtwork.swift
//  nodeseek
//
//  图标路径取自 nodeseek.com 线上 IconPark sprite（2026-09 抓取），
//  与官方 PWA/网页保持同源观感；颜色统一交给 tintColor。
//

enum NodeSeekIconName {
    static let chickenLeg = "chicken-leg"
    static let like = "good-one"
    static let oppose = "bad-one"
    static let favorite = "star-6negdgdk"
    static let joinDays = "stopwatch-start"
    static let level = "diamond"
    static let levelOutline = "diamond-two"
    static let topics = "write-6ncdp62p"
    static let edit = "edit"
    static let comments = "comments"
    static let likeFilled = "like"
    static let opposeFilled = "thumbs-down"
    static let collection = "personal-collection"
    static let stardust = "stardust3"
    static let follow = "concern"
    static let commentsAlt = "comments-6ncdh3ka"
    static let topicsAlt = "edit"
    static let messages = "receiver"
}

enum NodeSeekIconArtwork {
    static let chickenLeg = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="chicken-leg" viewBox="0 0 48 48" fill="none"><g><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M33.375 33.874c4.242-4.242 1.414-18.384-4.95-24.748-2.828-2.829-10.96-8.84-19.799 0-8.839 8.838-2.828 16.97 0 19.799 6.364 6.364 20.506 9.192 24.749 4.95Z"></path><path stroke-width="4" stroke="#000000" d="m41 41-7-7"></path><circle fill="#000000" transform="rotate(135 42.193 40.071)" r="2.5" cy="40.071" cx="42.193"></circle><circle fill="#000000" transform="rotate(135 40.072 42.192)" r="2.5" cy="42.192" cx="40.072"></circle><circle fill="#000000" r="2" cy="18" cx="17"></circle><circle fill="#000000" r="2" cy="21" cx="12"></circle><circle fill="#000000" r="2" cy="24" cx="17"></circle></g></svg>
"""#

    static let like = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="good-one" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="m35.911 41.544 5.37-19A2 2 0 0 0 39.356 20H27.875a1.094 1.094 0 0 1-1.066-1.34l.5-2.164c.458-1.985.605-4.03.436-6.06l-.092-1.103A5.02 5.02 0 0 0 26.2 6.2 4.096 4.096 0 0 0 23.304 5h-.24c-.657 0-1.262.356-1.58.93l-2.659 4.785a12.962 12.962 0 0 1-5.124 5.085l-6.659 3.63A2 2 0 0 0 6 21.188V41a2 2 0 0 0 2 2h25.987a2 2 0 0 0 1.924-1.456Z"></path></svg>
"""#

    static let oppose = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="bad-one" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="m35.911 6.456 5.37 19A2 2 0 0 1 39.356 28H27.875c-.704 0-1.224.654-1.066 1.34l.5 2.164c.458 1.985.605 4.03.436 6.06l-.092 1.103A5.02 5.02 0 0 1 26.2 41.8a4.096 4.096 0 0 1-2.896 1.2h-.24a1.809 1.809 0 0 1-1.58-.93l-2.659-4.785a12.962 12.962 0 0 0-5.124-5.084l-6.659-3.633A2 2 0 0 1 6 26.814V7a2 2 0 0 1 2-2h25.987a2 2 0 0 1 1.924 1.456Z"></path></svg>
"""#

    static let favorite = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="star-6negdgdk" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-width="4" stroke="#000000" d="m23.999 5-6.113 12.478L4 19.49l10.059 9.834L11.654 43 24 36.42 36.345 43 33.96 29.325 44 19.491l-13.809-2.013L24 5Z"></path></svg>
"""#

    static let joinDays = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="stopwatch-start" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-width="4" stroke="#000000" d="M24 44c9.389 0 17-7.611 17-17s-7.611-17-17-17S7 17.611 7 27s7.611 17 17 17Z"></path><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M18 4h12m-6 15v8m8 0h-8m0-23v4"></path></svg>
"""#

    static let level = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="diamond" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M10.636 5h26.728L45 18.3 24 43 3 18.3 10.636 5Z" clip-rule="evenodd"></path><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M10.636 5 24 43 37.364 5M3 18.3h42"></path><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M15.41 18.3 24 5l8.591 13.3"></path></svg>
"""#

    static let levelOutline = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="diamond-two" viewBox="0 0 48 48" fill="none"><path stroke-width="4" stroke="#000000" d="m8.923 22.788 13.486-17.7a2 2 0 0 1 3.182 0l13.486 17.7a2 2 0 0 1 0 2.424l-13.486 17.7a2 2 0 0 1-3.182 0l-13.486-17.7a2 2 0 0 1 0-2.424Z"></path></svg>
"""#

    static let topics = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="write-6ncdp62p" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-width="4" stroke="#000000" d="M5.325 43.5h8.485l31.113-31.113-8.486-8.485L5.325 35.015V43.5Z"></path><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="m27.952 12.387 8.485 8.485"></path></svg>
"""#

    static let edit = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="edit" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M7 42h36"></path><path stroke-linejoin="round" stroke-width="4" stroke="#000000" d="M11 26.72V34h7.317L39 13.308 31.695 6 11 26.72Z"></path></svg>
"""#

    static let comments = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="comments" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M33 38H22v-8h14v-8h8v16h-5l-3 3-3-3Z"></path><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M4 6h32v24H17l-4 4-4-4H4V6Z"></path><path stroke-linecap="round" stroke-width="4" stroke="#000000" d="M12 22h6m-6-8h12"></path></svg>
"""#

    /// PWA 统计卡"评论数"实际使用的变体。
    static let commentsAlt = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="comments-6ncdh3ka" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M33 38H22v-8h14v-8h8v16h-5l-3 3-3-3Z"></path><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M4 6h32v24H17l-4 4-4-4H4V6Z"></path><path stroke-linecap="round" stroke-width="4" stroke="#000000" d="M12 22h6m-6-8h12"></path></svg>
"""#

    /// PWA 统计卡"主题帖"实际使用的编辑图标。
    static let topicsAlt = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="edit" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M7 42h36"></path><path stroke-linejoin="round" stroke-width="4" stroke="#000000" d="M11 26.72V34h7.317L39 13.308 31.695 6 11 26.72Z"></path></svg>
"""#

    static let likeFilled = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="like" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M15 8C8.925 8 4 12.925 4 19c0 11 13 21 20 23.326C31 40 44 30 44 19c0-6.075-4.925-11-11-11-3.72 0-7.01 1.847-9 4.674A10.987 10.987 0 0 0 15 8Z"></path></svg>
"""#

    static let opposeFilled = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="thumbs-down" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-width="4" stroke="#000000" d="M20.38 29.4v7.2a5.4 5.4 0 0 0 5.4 5.4l7.2-16.2V6H12.062a3.6 3.6 0 0 0-3.6 3.06L5.98 25.26a3.6 3.6 0 0 0 3.6 4.14h10.8Z"></path><path stroke-linejoin="round" stroke-width="4" stroke="#000000" d="M32.98 6h4.806a4.158 4.158 0 0 1 4.194 3.6v12.6c-.283 2.09-2.086 3.838-4.194 3.8H32.98V6Z"></path></svg>
"""#

    static let collection = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="personal-collection" viewBox="0 0 48 48" fill="none"><circle stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" r="7" cy="11" cx="24"></circle><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M4 41c0-8.837 8.059-16 18-16m9.85 3C29.724 28 28 30.009 28 32.486c0 4.487 4.55 8.565 7 9.514 2.45-.949 7-5.027 7-9.514C42 30.01 40.276 28 38.15 28c-1.302 0-2.453.753-3.15 1.906C34.303 28.753 33.152 28 31.85 28Z"></path></svg>
"""#

    /// stardust3 是填充型图标（原站用 currentColor 填充），补 stroke+fill 保证 SVGKit/tint 可见。
    static let stardust = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="stardust3" viewBox="0 0 24 24" fill="none"><path stroke-linejoin="round" stroke-linecap="round" stroke-width="2" stroke="#000000" fill="#000000" d="M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594zM20 2v4m2-2h-4"></path><circle fill="#000000" stroke="#000000" stroke-width="1" r="2" cy="20" cx="4"></circle></svg>
"""#

    static let follow = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="concern" viewBox="0 0 48 48" fill="none"><path stroke-linecap="round" stroke-width="4" stroke="#000000" d="M10.858 9.858A19.937 19.937 0 0 0 5 24a19.937 19.937 0 0 0 5.858 14.142m28.284 0A19.937 19.937 0 0 0 45 24a19.937 19.937 0 0 0-5.858-14.142M34.9 33.9A13.956 13.956 0 0 0 39 24a13.96 13.96 0 0 0-4.1-9.9m-19.8 0A13.956 13.956 0 0 0 11 24a13.96 13.96 0 0 0 4.1 9.9"></path><path stroke-linejoin="round" stroke-width="4" stroke="#000000" d="M28.182 20C30.29 20 32 21.612 32 23.6c0 2.588-2.546 4.8-3.818 6-.849.8-1.91 1.6-3.182 2.4-1.273-.8-2.333-1.6-3.182-2.4-1.273-1.2-3.818-3.412-3.818-6 0-1.988 1.71-3.6 3.818-3.6 1.328 0 2.498.64 3.182 1.61.684-.97 1.854-1.61 3.182-1.61Z"></path></svg>
"""#

    static let messages = #"""
<svg xmlns="http://www.w3.org/2000/svg" id="receiver" viewBox="0 0 48 48" fill="none"><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M9.858 38.142c7.81 7.81 20.474 7.81 28.284 0L9.858 9.858c-7.81 7.81-7.81 20.474 0 28.284ZM33.9 33.9l5.27-21.986M24 24l13.172-13.172M14.1 14.1l21.986-5.27M44 8a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z"></path></svg>
"""#

}
