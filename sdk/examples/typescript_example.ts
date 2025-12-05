/**
 * TypeScript 示例模块
 * 
 * 这个文件展示了如何使用 TypeScript 编写漫画模块
 * 编译后的 .js 文件可以被 App 加载
 */

import type {
    ModuleInfo,
    Category,
    ComicSimple,
    ComicDetail,
    Chapter,
    ChapterImages,
    ImageInfo,
    ComicListResponse,
    PageInfo,
    GetComicListParams,
    GetComicDetailParams,
    GetChapterImagesParams,
    SearchParams,
    IComicModule
} from '../src/index';

// 模块元信息
const moduleInfo: ModuleInfo = {
    id: "typescript_example",
    name: "TypeScript 示例",
    version: "1.0.0",
    description: "使用 TypeScript 编写的示例模块"
};

/**
 * 获取分类列表
 */
function getCategories(): Category[] {
    return [
        { id: "popular", name: "人气榜", cover: null },
        { id: "latest", name: "最新", cover: null },
        { id: "completed", name: "完结", cover: null },
    ];
}

/**
 * 获取漫画列表
 */
function getComicList(params: GetComicListParams): ComicListResponse {
    const { categoryId, page } = params;
    
    const comics: ComicSimple[] = [];
    for (let i = 0; i < 20; i++) {
        const idx = (page - 1) * 20 + i + 1;
        comics.push({
            id: `ts_comic_${categoryId}_${idx}`,
            title: `TypeScript 漫画 ${idx}`,
            cover: `https://via.placeholder.com/200x300/4A90D9/white?text=TS${idx}`,
            author: `TS作者 ${idx % 5}`,
            update_info: `第 ${Math.floor(Math.random() * 200) + 1} 话`
        });
    }
    
    const pageInfo: PageInfo = {
        page,
        page_size: 20,
        total: 100,
        has_more: page < 5
    };
    
    return { comics, page_info: pageInfo };
}

/**
 * 获取漫画详情
 */
function getComicDetail(params: GetComicDetailParams): ComicDetail {
    const { comicId } = params;
    
    const chapters: Chapter[] = [];
    for (let i = 1; i <= 100; i++) {
        chapters.push({
            id: `${comicId}_ch_${i}`,
            title: `第 ${i} 话: 精彩内容`,
            update_time: `2024-${String((i % 12) + 1).padStart(2, '0')}-15`
        });
    }
    
    return {
        id: comicId,
        title: `TypeScript 漫画: ${comicId}`,
        cover: `https://via.placeholder.com/400x600/4A90D9/white?text=${comicId}`,
        author: "TypeScript 作者",
        description: "这是一个使用 TypeScript 编写的示例模块生成的漫画详情。TypeScript 提供了完整的类型检查，让开发更加安全可靠。",
        status: "连载中",
        tags: ["TypeScript", "示例", "开发者"],
        chapters,
        update_time: "2024-12-05"
    };
}

/**
 * 获取章节图片
 */
function getChapterImages(params: GetChapterImagesParams): ChapterImages {
    const { chapterId } = params;
    
    const images: ImageInfo[] = [];
    const count = Math.floor(Math.random() * 15) + 10;
    
    for (let i = 1; i <= count; i++) {
        images.push({
            url: `https://via.placeholder.com/800x1200/4A90D9/white?text=Page${i}`,
            width: 800,
            height: 1200,
            headers: null
        });
    }
    
    return {
        chapter_id: chapterId,
        images
    };
}

/**
 * 搜索漫画
 */
function search(params: SearchParams): ComicListResponse {
    const { keyword, page, page_size } = params;
    
    const comics: ComicSimple[] = [];
    for (let i = 0; i < page_size; i++) {
        const idx = (page - 1) * page_size + i + 1;
        comics.push({
            id: `ts_search_${keyword}_${idx}`,
            title: `[TS] ${keyword} 搜索结果 ${idx}`,
            cover: `https://via.placeholder.com/200x300/4A90D9/white?text=Search${idx}`,
            author: `作者 ${idx % 3}`,
            update_info: `相关度: ${100 - idx}%`
        });
    }
    
    const pageInfo: PageInfo = {
        page,
        page_size,
        total: 30,
        has_more: page < 2
    };
    
    return { comics, page_info: pageInfo };
}

// 导出模块
export {
    moduleInfo,
    getCategories,
    getComicList,
    getComicDetail,
    getChapterImages,
    search
};
