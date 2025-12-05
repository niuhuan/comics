/**
 * 示例漫画模块
 * 
 * 这是一个用于演示的模块，返回模拟数据
 */

// 模块元信息
const moduleInfo = {
    id: "example_module",
    name: "示例模块",
    version: "1.0.0",
    description: "这是一个用于演示的示例模块，返回模拟数据"
};

/**
 * 获取分类列表
 * @returns {Array<{id: string, name: string, cover?: string}>}
 */
function getCategories() {
    return [
        { id: "hot", name: "热门推荐", cover: null },
        { id: "new", name: "最新更新", cover: null },
        { id: "finished", name: "已完结", cover: null },
        { id: "action", name: "动作", cover: null },
        { id: "romance", name: "恋爱", cover: null },
        { id: "comedy", name: "搞笑", cover: null },
    ];
}

/**
 * 获取漫画列表
 * @param {{categoryId: string, page: number}} params
 * @returns {{comics: Array, page_info: Object}}
 */
function getComicList(params) {
    const { categoryId, page } = params;
    
    // 模拟数据
    const comics = [];
    for (let i = 0; i < 20; i++) {
        const idx = (page - 1) * 20 + i + 1;
        comics.push({
            id: `comic_${categoryId}_${idx}`,
            title: `${categoryId} 漫画 ${idx}`,
            cover: `https://via.placeholder.com/200x300?text=Comic${idx}`,
            author: `作者 ${idx % 10}`,
            update_info: `更新至第 ${Math.floor(Math.random() * 100) + 1} 话`
        });
    }
    
    return {
        comics: comics,
        page_info: {
            page: page,
            page_size: 20,
            total: 100,
            has_more: page < 5
        }
    };
}

/**
 * 获取漫画详情
 * @param {{comicId: string}} params
 * @returns {Object}
 */
function getComicDetail(params) {
    const { comicId } = params;
    
    const chapters = [];
    for (let i = 1; i <= 50; i++) {
        chapters.push({
            id: `${comicId}_chapter_${i}`,
            title: `第 ${i} 话`,
            update_time: `2024-${String(Math.floor(Math.random() * 12) + 1).padStart(2, '0')}-${String(Math.floor(Math.random() * 28) + 1).padStart(2, '0')}`
        });
    }
    
    return {
        id: comicId,
        title: `漫画: ${comicId}`,
        cover: `https://via.placeholder.com/400x600?text=${comicId}`,
        author: "示例作者",
        description: "这是一个示例漫画的描述，用于演示模块的功能。这部漫画讲述了一个关于冒险和友情的故事...",
        status: "连载中",
        tags: ["动作", "冒险", "热血", "奇幻"],
        chapters: chapters,
        update_time: "2024-12-05"
    };
}

/**
 * 获取章节图片
 * @param {{comicId: string, chapterId: string}} params
 * @returns {Object}
 */
function getChapterImages(params) {
    const { comicId, chapterId } = params;
    
    const images = [];
    const pageCount = Math.floor(Math.random() * 20) + 10;
    
    for (let i = 1; i <= pageCount; i++) {
        images.push({
            url: `https://via.placeholder.com/800x1200?text=Page${i}`,
            width: 800,
            height: 1200,
            headers: null
        });
    }
    
    return {
        chapter_id: chapterId,
        images: images
    };
}

/**
 * 搜索漫画
 * @param {{keyword: string, page: number, page_size: number}} params
 * @returns {{comics: Array, page_info: Object}}
 */
function search(params) {
    const { keyword, page, page_size } = params;
    
    const comics = [];
    for (let i = 0; i < page_size; i++) {
        const idx = (page - 1) * page_size + i + 1;
        comics.push({
            id: `search_${keyword}_${idx}`,
            title: `搜索结果: ${keyword} - ${idx}`,
            cover: `https://via.placeholder.com/200x300?text=Search${idx}`,
            author: `作者 ${idx % 5}`,
            update_info: `匹配度: ${100 - idx}%`
        });
    }
    
    return {
        comics: comics,
        page_info: {
            page: page,
            page_size: page_size,
            total: 50,
            has_more: page < 3
        }
    };
}

// 导出模块
if (typeof module !== 'undefined') {
    module.exports = {
        moduleInfo,
        getCategories,
        getComicList,
        getComicDetail,
        getChapterImages,
        search
    };
}
