use rquickjs::{Context, Runtime, Function, Object, Value, IntoJs, FromJs};
use std::sync::Arc;
use tokio::sync::Mutex;
use anyhow::Result;

use super::bindings;

/// JavaScript 运行时封装
pub struct JsRuntime {
    runtime: Runtime,
    context: Context,
}

impl JsRuntime {
    /// 创建新的 JS 运行时
    pub fn new() -> Result<Self> {
        let runtime = Runtime::new()?;
        
        // 设置内存限制 (64MB)
        runtime.set_memory_limit(64 * 1024 * 1024);
        
        // 设置最大栈大小
        runtime.set_max_stack_size(1024 * 1024);
        
        let context = Context::full(&runtime)?;
        
        // 注册全局绑定
        context.with(|ctx| -> Result<()> {
            bindings::register_all(&ctx)?;
            Ok(())
        })?;
        
        Ok(Self { runtime, context })
    }

    /// 执行 JavaScript 代码
    pub fn eval<T>(&self, code: &str) -> Result<T>
    where
        T: for<'js> FromJs<'js>,
    {
        self.context.with(|ctx| {
            let result: T = ctx.eval(code)?;
            Ok(result)
        })
    }

    /// 执行 JavaScript 代码，返回字符串结果
    pub fn eval_string(&self, code: &str) -> Result<String> {
        self.context.with(|ctx| {
            let result: Value = ctx.eval(code)?;
            match result.type_of() {
                rquickjs::Type::String => {
                    let s: String = result.get()?;
                    Ok(s)
                }
                rquickjs::Type::Object => {
                    // 尝试 JSON.stringify
                    let json: Object = ctx.globals().get("JSON")?;
                    let stringify: Function = json.get("stringify")?;
                    let json_str: String = stringify.call((result,))?;
                    Ok(json_str)
                }
                _ => {
                    let s: String = result.get().unwrap_or_else(|_| "undefined".to_string());
                    Ok(s)
                }
            }
        })
    }

    /// 加载并执行模块脚本
    pub fn load_module(&self, module_id: &str, script: &str) -> Result<()> {
        self.context.with(|ctx| {
            // 设置当前模块 ID 到全局
            let globals = ctx.globals();
            globals.set("__MODULE_ID__", module_id)?;
            
            // 执行脚本
            let _: Value = ctx.eval(script)?;
            
            Ok(())
        })
    }

    /// 调用模块中的函数
    pub fn call_function<T>(&self, func_name: &str, args: impl IntoIterator<Item = String>) -> Result<T>
    where
        T: for<'js> FromJs<'js>,
    {
        self.context.with(|ctx| {
            let globals = ctx.globals();
            let func: Function = globals.get(func_name)?;
            
            let args_vec: Vec<String> = args.into_iter().collect();
            
            // 使用元组调用，如果只有一个参数
            if args_vec.len() == 1 {
                let result: T = func.call((args_vec[0].clone(),))?;
                return Ok(result);
            }
            
            // 没有参数的情况
            if args_vec.is_empty() {
                let result: T = func.call(())?;
                return Ok(result);
            }
            
            // 多个参数，使用 JSON 传递
            let json_args = serde_json::to_string(&args_vec)?;
            let json: Object = globals.get("JSON")?;
            let parse: Function = json.get("parse")?;
            let parsed_args: Value = parse.call((json_args,))?;
            let result: T = func.call((parsed_args,))?;
            Ok(result)
        })
    }

    /// 调用模块中的函数，返回 JSON 字符串
    pub fn call_function_json(&self, func_name: &str, args_json: &str) -> Result<String> {
        self.context.with(|ctx| {
            let globals = ctx.globals();
            let func: Function = globals.get(func_name)?;
            
            // 解析 JSON 参数
            let json: Object = globals.get("JSON")?;
            let parse: Function = json.get("parse")?;
            let args: Value = parse.call((args_json,))?;
            
            // 调用函数
            let result: Value = func.call((args,))?;
            
            // 序列化结果
            let stringify: Function = json.get("stringify")?;
            let json_str: String = stringify.call((result,))?;
            
            Ok(json_str)
        })
    }

    /// 检查函数是否存在
    pub fn has_function(&self, func_name: &str) -> bool {
        self.context.with(|ctx| {
            let globals = ctx.globals();
            let result: std::result::Result<Function, _> = globals.get(func_name);
            result.is_ok()
        })
    }

    /// 获取全局变量
    pub fn get_global<T>(&self, name: &str) -> Result<T>
    where
        T: for<'js> FromJs<'js>,
    {
        self.context.with(|ctx| {
            let globals = ctx.globals();
            let value: T = globals.get(name)?;
            Ok(value)
        })
    }

    /// 设置全局变量
    pub fn set_global<T>(&self, name: &str, value: T) -> Result<()>
    where
        T: for<'js> IntoJs<'js>,
    {
        self.context.with(|ctx| {
            let globals = ctx.globals();
            globals.set(name, value)?;
            Ok(())
        })
    }
}

/// 线程安全的 JS 运行时
pub type SharedJsRuntime = Arc<Mutex<JsRuntime>>;

pub fn create_shared_runtime() -> Result<SharedJsRuntime> {
    let runtime = JsRuntime::new()?;
    Ok(Arc::new(Mutex::new(runtime)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_eval() {
        let runtime = JsRuntime::new().unwrap();
        let result: i32 = runtime.eval("1 + 2").unwrap();
        assert_eq!(result, 3);
    }

    #[test]
    fn test_eval_string() {
        let runtime = JsRuntime::new().unwrap();
        let result = runtime.eval_string("'hello' + ' world'").unwrap();
        assert_eq!(result, "hello world");
    }

    #[test]
    fn test_json() {
        let runtime = JsRuntime::new().unwrap();
        let result = runtime.eval_string("JSON.stringify({a: 1, b: 2})").unwrap();
        assert_eq!(result, r#"{"a":1,"b":2}"#);
    }
}
