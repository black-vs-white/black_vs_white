use std::{
    io::{BufWriter, Write},
    path::PathBuf,
};

use anyhow::bail;
use clap::Parser;

#[derive(Parser)]
struct Args {
    markdown_files: Vec<PathBuf>,
    #[clap(short, long)]
    attributions_file: PathBuf,
    #[clap(short, long)]
    output: Option<PathBuf>,
}

#[derive(Debug)]
#[allow(dead_code)]
struct Attribution {
    file: PathBuf,
    description: String,
    attribution: String,
    link: Option<String>,
    license: Option<String>,
}

fn parse_line(
    line: &str,
    i: usize,
    file: &mut Option<PathBuf>,
    description: &mut Option<String>,
    attribution: &mut Option<String>,
    link: &mut Option<String>,
    license: &mut Option<String>,
) -> anyhow::Result<Option<Attribution>> {
    let lowercase_line = line.to_lowercase();
    let lower_trimmed_line = lowercase_line.trim();
    if lower_trimmed_line.starts_with("file:") {
        if file.is_some() {
            bail!("Duplicate 'file:' attribute at line {}", i + 1);
        }
        *file = Some(line["file:".len()..].trim().to_string().into());
    } else if lower_trimmed_line.starts_with("description:") {
        if attribution.is_some() {
            bail!("Duplicate 'description:' attribute at line {}", i + 1);
        }
        *description = Some(line["description:".len()..].trim().to_string());
    } else if lower_trimmed_line.starts_with("attribution:") {
        if attribution.is_some() {
            bail!("Duplicate 'attribution:' attribute at line {}", i + 1);
        }
        *attribution = Some(line["attribution:".len()..].trim().to_string());
    } else if lower_trimmed_line.starts_with("link:") {
        if link.is_some() {
            bail!("Duplicate 'link:' attribute at line {}", i + 1);
        }
        *link = Some(line["link:".len()..].trim().to_string());
    } else if lower_trimmed_line.starts_with("license:") {
        if license.is_some() {
            bail!("Duplicate 'license:' attribute at line {}", i + 1);
        }
        *license = Some(line["license:".len()..].trim().to_string());
    } else if line.trim() == "---" {
        match (file.take(), attribution.take(), description.take()) {
            (Some(file), Some(attribution), Some(description)) => {
                return Ok(Some(Attribution {
                    file,
                    description,
                    attribution,
                    link: link.take(),
                    license: license.take(),
                }));
            }
            (None, None, None) => {
                bail!(
                    "Missing 'file:', 'description:' and 'attribution:' attributes at line {}",
                    i + 1
                );
            }
            (None, None, _) => {
                bail!(
                    "Missing 'file:' and 'attribution:' attributes at line {}",
                    i + 1
                );
            }
            (None, _, None) => {
                bail!(
                    "Missing 'file:' and 'description:' attributes at line {}",
                    i + 1
                );
            }
            (_, None, None) => {
                bail!(
                    "Missing 'attribution:' and 'description:' attributes at line {}",
                    i + 1
                );
            }
            (_, _, None) => {
                bail!("Missing 'description:' attribute at line {}", i + 1);
            }
            (None, _, _) => {
                bail!("Missing 'file:' attribute at line {}", i + 1);
            }
            (_, None, _) => {
                bail!("Missing 'attribution:' attribute at line {}", i + 1);
            }
        }
    } else {
        bail!("Invalid entry at line {}: {line}", i + 1);
    }

    Ok(None)
}

fn main() -> anyhow::Result<()> {
    let Args {
        markdown_files,
        attributions_file,
        output,
    } = Args::parse();

    let attr = std::fs::read_to_string(&attributions_file)?;
    let mut attributions = Vec::new();
    let mut file = None;
    let mut description = None;
    let mut attribution = None;
    let mut link = None;
    let mut license = None;
    let mut find_next_entry = false;
    let mut errors = Vec::new();
    let mut last_line = 0;
    for (i, line) in attr.lines().enumerate() {
        last_line = i;
        if line.trim().is_empty() {
            continue;
        }
        if find_next_entry {
            if line.trim() == "---" {
                _ = file.take();
                _ = description.take();
                _ = attribution.take();
                _ = link.take();
                _ = license.take();
                find_next_entry = false;
            }
            continue;
        }
        match parse_line(
            line,
            i,
            &mut file,
            &mut description,
            &mut attribution,
            &mut link,
            &mut license,
        ) {
            Ok(Some(attribution)) => attributions.push(attribution),
            Ok(None) => {}
            Err(e) => {
                errors.push(e.to_string());
                find_next_entry = true;
            }
        }
    }
    if file.is_some()
        || attribution.is_some()
        || description.is_some()
        || link.is_some()
        || license.is_some()
    {
        match parse_line(
            "---",
            last_line,
            &mut file,
            &mut description,
            &mut attribution,
            &mut link,
            &mut license,
        ) {
            Ok(Some(attribution)) => attributions.push(attribution),
            Ok(None) => {}
            Err(e) => {
                errors.push(e.to_string());
            }
        }
    }
    if !errors.is_empty() {
        for error in errors {
            eprintln!("{}", error);
        }
        bail!("Failed to parse ATTRIBUTIONS.txt");
    }

    let mut attribution_text = BufWriter::new(Vec::new());
    for Attribution {
        file: _,
        description,
        attribution,
        link,
        license,
    } in attributions
    {
        write!(
            attribution_text,
            r#"<li>{description}:<ul><li>{}<span class="redactor-unlink"></span></li>{}</ul></li>"#,
            link_or_attribution(link, attribution),
            license_or_none(license)
        )?;
    }

    let attribution_list = format!(
        r#"<ul>{}</ul>"#,
        String::from_utf8_lossy(attribution_text.buffer())
    );

    let mut description_text = BufWriter::new(Vec::new());
    for markdown_file in markdown_files {
        let markdown = std::fs::read_to_string(&markdown_file)?;

        write!(
            description_text,
            "<!-- {} -->\n{}\n\n",
            markdown_file
                .with_extension("")
                .file_name()
                .unwrap()
                .to_string_lossy(),
            markdown::to_html(markdown.trim())
        )?;
    }

    let final_text = format!(
        "{}<!-- {} -->\n{}",
        String::from_utf8_lossy(description_text.buffer()),
        attributions_file
            .with_extension("")
            .file_name()
            .unwrap()
            .to_string_lossy(),
        attribution_list
    );

    if let Some(output) = output {
        std::fs::write(output.clone(), final_text)?;
        println!("HTML written to {}", output.display());
    } else {
        println!("{}", final_text);
    }

    Ok(())
}

fn license_or_none(license: Option<String>) -> String {
    license
        .map(|license| format!("<li>{license}</li>"))
        .unwrap_or_default()
}

fn link_or_attribution(link: Option<String>, attribution: String) -> String {
    match link {
        Some(link) => format!(r#"<a target="_blank" href="{}">{}</a>"#, link, attribution),
        None => attribution,
    }
}
